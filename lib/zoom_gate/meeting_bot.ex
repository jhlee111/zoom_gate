defmodule ZoomGate.MeetingBot do
  @moduledoc """
  Pure Elixir Zoom Web SDK client.

  Connects directly to Zoom's RWG WebSocket. Supports two wire formats:

  - `as_type: 1` — plaintext JSON text frames (default)
  - `as_type: 2` — binary frames with 17-byte header (see `Frame`)

  Both modes support full waiting room management (detect, admit, deny).

  ## State Machine

      :initializing → :connecting → :active → :ended
                           ↓
                     :waiting_room → :reconnecting → :connecting → :active
                           ↓
                         :ended

  ## Integration

  Started by `ZoomGate.Session` as a child process. Reports events via:

      send(session_pid, {:meeting_bot_event, {event_type, payload}})
  """

  use GenServer
  require Logger
  require ZoomGate.MeetingBot.Protocol, as: Proto

  alias ZoomGate.MeetingBot.{Connection, Frame, Participant, Protocol}

  @keepalive_interval 60_000
  @heartbeat_check_interval 30_000
  @heartbeat_timeout 90_000
  @max_reconnect_attempts 5
  @initial_reconnect_delay 1_000

  defstruct [
    :meeting_number,
    :meeting_password,
    :display_name,
    :sdk_key,
    :sdk_secret,
    :zak,
    :session_pid,
    :conn,
    :stream,
    :join_info,
    :hardware_id,
    :meeting_info,
    :rwg_info,
    :cookies,
    :reconnect_timer,
    :analyzer,
    :last_heartbeat_at,
    :heartbeat_check_timer,
    role: 0,
    seq: 0,
    wire_seq: 0,
    last_recv_seq: 0,
    as_type: 1,
    status: :initializing,
    participants: %{},
    reconnect_attempts: 0
  ]

  # -- Public API --

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def rename(pid, user_id, old_name, new_name) do
    GenServer.call(pid, {:rename, user_id, old_name, new_name})
  end

  def send_chat(pid, dest_node_id, text) do
    GenServer.call(pid, {:chat, dest_node_id, text})
  end

  def expel(pid, user_id) do
    GenServer.call(pid, {:expel, user_id})
  end

  def put_on_hold(pid, user_id, hold) do
    GenServer.call(pid, {:put_on_hold, user_id, hold})
  end

  def admit_all(pid) do
    GenServer.call(pid, :admit_all)
  end

  def mute(pid, user_id, muted) do
    GenServer.call(pid, {:mute, user_id, muted})
  end

  def start_recording(pid), do: GenServer.call(pid, :start_recording)

  def stop_recording(pid), do: GenServer.call(pid, :stop_recording)

  def lock_sharing(pid, locked), do: GenServer.call(pid, {:lock_sharing, locked})

  def spotlight(pid, user_id, spotlight), do: GenServer.call(pid, {:spotlight, user_id, spotlight})

  def end_meeting(pid) do
    GenServer.call(pid, :end_meeting)
  end

  def leave(pid) do
    GenServer.call(pid, :leave)
  end

  def get_health(pid) do
    GenServer.call(pid, :get_health, 5_000)
  catch
    :exit, _ -> %{status: :unreachable}
  end

  def get_participants(pid) do
    GenServer.call(pid, :get_participants, 5_000)
  catch
    :exit, _ -> %{}
  end

  # -- GenServer --

  @impl true
  def init(opts) do
    state = %__MODULE__{
      meeting_number: Keyword.fetch!(opts, :meeting_number),
      meeting_password: Keyword.get(opts, :password, ""),
      display_name: Keyword.get(opts, :display_name, "ZoomGate-Bot"),
      sdk_key: Keyword.fetch!(opts, :sdk_key),
      sdk_secret: Keyword.fetch!(opts, :sdk_secret),
      zak: Keyword.get(opts, :zak, ""),
      role: Keyword.get(opts, :role, 0),
      session_pid: Keyword.fetch!(opts, :session_pid),
      hardware_id: UUID.uuid4(),
      as_type: Keyword.get(opts, :as_type, 1),
      analyzer: Keyword.get(opts, :analyzer)
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    state = %{state | status: :connecting}

    case Connection.connect(state) do
      {:ok, conn, stream, meeting_info, rwg_info, cookies} ->
        schedule_keepalive()
        schedule_heartbeat_check()

        {:noreply,
         %{
           state
           | conn: conn,
             stream: stream,
             meeting_info: meeting_info,
             rwg_info: rwg_info,
             cookies: cookies,
             last_heartbeat_at: System.monotonic_time(:millisecond),
             status: :connecting
         }}

      {:error, reason} ->
        Logger.error("[MeetingBot] Connection failed: #{inspect(reason)}")
        notify(state, {:error, %{message: "Connection failed: #{inspect(reason)}"}})
        {:stop, {:connection_failed, reason}, state}
    end
  end

  @impl true
  def handle_continue(:reconnect, state) do
    state = %{state | status: :connecting}

    extra_params =
      case state.reconnect_opts do
        opts when is_map(opts) ->
          opts
          |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
          |> Map.new()

        opts when is_list(opts) ->
          opts
          |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
          |> Map.new()

        _ ->
          %{}
      end

    # If we have meeting_info and rwg_info, try a websocket reconnect.
    # Otherwise, do a full connect from scratch.
    {result, new_rwg_info, new_cookies} =
      if state.meeting_info && state.rwg_info do
        case Connection.reconnect(state, state.meeting_info, state.rwg_info, state.cookies, extra_params) do
          {:ok, conn, stream} -> {{:ok, conn, stream}, state.rwg_info, state.cookies}
          error -> {error, state.rwg_info, state.cookies}
        end
      else
        case Connection.connect(state) do
          {:ok, conn, stream, _meeting_info, rwg_info, cookies} ->
            {{:ok, conn, stream}, rwg_info, cookies}

          error ->
            {error, state.rwg_info, state.cookies}
        end
      end

    case result do
      {:ok, conn, stream} ->
        schedule_keepalive()
        schedule_heartbeat_check()

        {:noreply,
         %{
           state
           | conn: conn,
             stream: stream,
             rwg_info: new_rwg_info,
             cookies: new_cookies,
             last_heartbeat_at: System.monotonic_time(:millisecond),
             status: :connecting,
             reconnect_attempts: 0
         }}

      {:error, reason} ->
        Logger.error("[MeetingBot] Reconnection failed: #{inspect(reason)}")
        attempt = state.reconnect_attempts + 1

        if attempt < @max_reconnect_attempts do
          delay = @initial_reconnect_delay * Integer.pow(2, attempt - 1)
          delay = min(delay, 30_000)
          Logger.info("[MeetingBot] Retrying in #{delay}ms (attempt #{attempt})")
          timer = Process.send_after(self(), :retry_reconnect, delay)

          {:noreply,
           %{
             state
             | status: :reconnecting,
               reconnect_attempts: attempt,
               reconnect_timer: timer
           }}
        else
          notify(state, {:error, %{message: "Reconnection failed after #{attempt} attempts"}})
          {:stop, {:reconnection_failed, reason}, state}
        end
    end
  end

  # -- Commands --

  @impl true
  def handle_call({:rename, user_id, old_name, new_name}, _from, state) do
    state =
      send_evt(state, Proto.evt_rename_req(), %{
        id: user_id,
        dn2: Protocol.b64_encode(new_name),
        olddn2: Protocol.b64_encode(old_name)
      })

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:chat, dest_node_id, text}, _from, state) do
    state =
      send_evt(state, Proto.evt_chat_req(), %{
        destNodeID: dest_node_id,
        sn: Protocol.b64_encode(state.join_info["zoomID"] || ""),
        text: Protocol.b64_encode(text)
      })

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:expel, user_id}, _from, state) do
    state = send_evt(state, Proto.evt_expel_req(), %{id: user_id})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:put_on_hold, user_id, hold}, _from, state) do
    state = send_evt(state, Proto.evt_put_on_hold_req(), %{id: user_id, bHold: hold})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:admit_all, _from, state) do
    state = send_evt(state, Proto.evt_admit_all_req(), %{})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:mute, user_id, muted}, _from, state) do
    state = send_evt(state, Proto.evt_mute_req(), %{id: user_id, mute: muted})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:start_recording, _from, state) do
    state = send_evt(state, Proto.evt_record_req(), %{bRecord: true, bPause: false})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stop_recording, _from, state) do
    state = send_evt(state, Proto.evt_record_req(), %{bRecord: false, bPause: false})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:lock_sharing, locked}, _from, state) do
    state = send_evt(state, Proto.evt_lock_sharing_req(), %{lockShare: if(locked, do: 1, else: 0)})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:spotlight, user_id, spotlight}, _from, state) do
    state = send_evt(state, Proto.evt_spotlight_req(), %{id: user_id, bSpotlight: spotlight})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_participants, _from, state) do
    alias ZoomGate.MeetingBot.Participant

    participants =
      state.participants
      |> Enum.map(fn {id, p} -> {id, Participant.to_event_map(p)} end)
      |> Map.new()

    {:reply, participants, state}
  end

  @impl true
  def handle_call(:get_health, _from, state) do
    health = %{
      status: state.status,
      last_heartbeat_at: state.last_heartbeat_at,
      heartbeat_age_ms:
        if(state.last_heartbeat_at,
          do: System.monotonic_time(:millisecond) - state.last_heartbeat_at,
          else: nil
        ),
      reconnect_attempts: state.reconnect_attempts,
      participant_count: map_size(state.participants)
    }

    {:reply, health, state}
  end

  @impl true
  def handle_call(:end_meeting, _from, state) do
    state = send_evt(state, Proto.evt_end_req(), %{})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:leave, _from, state) do
    state = send_evt(state, Proto.evt_leave_req(), %{})
    {:reply, :ok, state}
  end

  # -- Incoming WebSocket Messages --

  @impl true
  def handle_info(:keepalive, state) do
    state = send_evt(state, Proto.evt_keepalive(), nil)
    schedule_keepalive()
    {:noreply, state}
  end

  @impl true
  def handle_info(:retry_reconnect, state) do
    {:noreply, state, {:continue, :reconnect}}
  end

  @impl true
  def handle_info(:trigger_reconnect, state) do
    attempt_reconnect(state)
  end

  @impl true
  def handle_info(:heartbeat_check, state) do
    if state.status == :active && state.last_heartbeat_at do
      elapsed = System.monotonic_time(:millisecond) - state.last_heartbeat_at

      if elapsed > @heartbeat_timeout do
        Logger.warning("[MeetingBot] Heartbeat timeout (#{elapsed}ms), triggering reconnect")
        attempt_reconnect(state)
      else
        schedule_heartbeat_check()
        {:noreply, state}
      end
    else
      schedule_heartbeat_check()
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:gun_ws, _conn, _stream, {:text, data}}, state) do
    if state.analyzer, do: send(state.analyzer, {:raw_ws, :incoming, data})

    case Protocol.decode(data) do
      {:ok, msg} ->
        state = handle_zoom_message(msg, state)
        {:noreply, state}

      {:error, _} ->
        Logger.warning("[MeetingBot] Unparseable message: #{data}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:gun_ws, _conn, _stream, {:binary, data}}, state) do
    if state.analyzer, do: send(state.analyzer, {:raw_ws, :incoming, {:binary, data}})

    case Frame.decode(data) do
      {:data, json, server_seq} ->
        state = %{state | last_recv_seq: max(state.last_recv_seq, server_seq)}

        case Protocol.decode(json) do
          {:ok, msg} ->
            {:noreply, handle_zoom_message(msg, state)}

          {:error, _} ->
            Logger.debug("[MeetingBot] Binary frame non-JSON payload")
            {:noreply, state}
        end

      {:handshake, _frame} ->
        Logger.info("[MeetingBot] Received server handshake")
        {:noreply, state}

      {:ping, frame} ->
        pong = Frame.encode_pong(frame)
        :gun.ws_send(state.conn, state.stream, {:binary, pong})
        {:noreply, state}

      {:data_binary, _payload, server_seq} ->
        state = %{state | last_recv_seq: max(state.last_recv_seq, server_seq)}
        {:noreply, state}

      {:pong, _} ->
        {:noreply, state}

      {:unknown, type} ->
        Logger.debug("[MeetingBot] Unknown binary frame type=0x#{Integer.to_string(type, 16)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:gun_ws, _conn, _stream, {:close, code, reason}}, state) do
    Logger.info("[MeetingBot] WebSocket closed: #{code} #{reason}")

    case state.status do
      :ended ->
        notify(state, {:meeting_ended, %{reason: :ws_closed}})
        {:stop, :normal, state}

      _ ->
        # Unexpected close — try reconnect
        attempt_reconnect(state)
    end
  end

  @impl true
  def handle_info({:gun_down, _conn, _proto, reason, _}, state) do
    Logger.error("[MeetingBot] Connection down: #{inspect(reason)}")

    case state.status do
      :ended ->
        {:stop, {:connection_down, reason}, state}

      _ ->
        attempt_reconnect(state)
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[MeetingBot] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # -- Zoom Message Handlers --

  defp handle_zoom_message(%{"evt" => Proto.evt_keepalive()} = msg, state) do
    Logger.debug("[MeetingBot] Heartbeat seq=#{msg["seq"]}")
    %{state | last_heartbeat_at: System.monotonic_time(:millisecond)}
  end

  defp handle_zoom_message(%{"evt" => Proto.evt_join_res(), "body" => body}, state) do
    res = body["res"]

    if res && res != 0 do
      Logger.error("[MeetingBot] Join rejected: res=#{res}")
      notify(state, {:error, %{message: "Join rejected", code: res}})
      %{state | status: :ended}
    else
      Logger.info(
        "[MeetingBot] Joined! participantID=#{body["participantID"]} role=#{body["role"]}"
      )

      notify(
        state,
        {:joined,
         %{
           meeting_id: state.meeting_number,
           participant_id: body["participantID"],
           user_id: body["userID"],
           role: body["role"]
         }}
      )

      %{state | join_info: body, status: :active}
    end
  end

  defp handle_zoom_message(%{"evt" => Proto.evt_roster(), "body" => body}, state) do
    {participants, events} = Participant.merge_roster(state.participants, body)

    Enum.each(events, fn event -> notify(state, event) end)

    %{state | participants: participants}
  end

  defp handle_zoom_message(%{"evt" => Proto.evt_hold_change(), "body" => body}, state) do
    user_id = body["id"]
    b_hold = body["bHold"]

    # Update participant's hold status
    state =
      case Map.get(state.participants, user_id) do
        nil ->
          state

        participant ->
          updated = %{participant | b_hold: b_hold}
          %{state | participants: Map.put(state.participants, user_id, updated)}
      end

    if b_hold do
      # Check if this is the bot being put on hold
      if user_id == state.join_info["participantID"] do
        Logger.info("[MeetingBot] Bot put in waiting room")
        # Save reconnect options from the body
        %{state | status: :waiting_room, reconnect_opts: body}
      else
        notify(
          state,
          {:waiting_room_join,
           %{
             zoom_user_id: user_id,
             display_name: get_participant_name(state, user_id)
           }}
        )

        state
      end
    else
      if user_id == state.join_info["participantID"] do
        Logger.info("[MeetingBot] Bot admitted from waiting room — reconnecting")
        %{state | status: :reconnecting}
      else
        notify(state, {:waiting_room_leave, %{zoom_user_id: user_id}})
        state
      end
    end
  end

  defp handle_zoom_message(%{"evt" => Proto.evt_chat_indication(), "body" => body}, state) do
    text =
      case body["text"] do
        t when is_binary(t) -> Protocol.b64_decode(t)
        _ -> ""
      end

    notify(state, {:chat_received, %{from_user_id: body["senderSN"], message: text}})
    state
  end

  defp handle_zoom_message(%{"evt" => Proto.evt_end(), "body" => body}, state) do
    reason = body["reason"] || 0

    if reason == 5 do
      # Reconnect signal (e.g., WaitingRoomFailover)
      Logger.info("[MeetingBot] Reconnect signal (reason=5, subReason=#{body["subReason"]})")
      send(self(), :trigger_reconnect)
      %{state | status: :reconnecting}
    else
      reason_atom = end_reason_atom(reason)
      Logger.info("[MeetingBot] Meeting ended: #{reason_atom} (reason=#{reason})")
      notify(state, {:meeting_ended, %{reason: reason_atom, code: reason}})
      %{state | status: :ended}
    end
  end

  defp handle_zoom_message(%{"evt" => Proto.evt_end()}, state) do
    Logger.info("[MeetingBot] Meeting ended (no body)")
    notify(state, {:meeting_ended, %{reason: :ended}})
    %{state | status: :ended}
  end

  defp handle_zoom_message(%{"evt" => Proto.evt_host_change(), "body" => body}, state) do
    Logger.info("[MeetingBot] Host changed to #{body["id"]}")
    notify(state, {:host_changed, %{new_host_id: body["id"]}})
    state
  end

  defp handle_zoom_message(%{"evt" => Proto.evt_attribute(), "body" => body}, state) do
    user_id = body["id"]

    case Map.get(state.participants, user_id) do
      nil ->
        notify(state, {:attribute_changed, %{zoom_user_id: user_id, changes: body}})
        state

      participant ->
        updated =
          participant
          |> maybe_update_field(:muted, body["muted"])
          |> maybe_update_field(:video_on, body["bVideoOn"])

        %{state | participants: Map.put(state.participants, user_id, updated)}
    end
  end

  defp handle_zoom_message(%{"evt" => Proto.evt_option(), "body" => body}, state) do
    notify(state, {:meeting_option_changed, body})
    state
  end

  defp handle_zoom_message(%{"evt" => evt, "body" => body}, state) do
    notify(state, {:raw_event, %{evt: evt, body: body}})
    state
  end

  defp handle_zoom_message(%{"evt" => evt}, state) do
    notify(state, {:raw_event, %{evt: evt, body: nil}})
    state
  end

  # -- Helpers --

  defp send_evt(state, evt, body) do
    seq = state.seq + 1
    json = Protocol.encode(evt, body, seq)
    if state.analyzer, do: send(state.analyzer, {:raw_ws, :outgoing, json})

    case state.as_type do
      2 ->
        wire_seq = state.wire_seq + 1
        timestamp = monotonic_timestamp()
        frame = Frame.encode_data(json, wire_seq, timestamp, state.last_recv_seq)
        :gun.ws_send(state.conn, state.stream, {:binary, frame})
        %{state | seq: seq, wire_seq: wire_seq}

      _ ->
        :gun.ws_send(state.conn, state.stream, {:text, json})
        %{state | seq: seq}
    end
  end

  defp monotonic_timestamp do
    System.monotonic_time(:millisecond)
    |> rem(0xFFFFFFFF)
    |> max(0)
  end

  defp schedule_keepalive do
    Process.send_after(self(), :keepalive, @keepalive_interval)
  end

  defp schedule_heartbeat_check do
    Process.send_after(self(), :heartbeat_check, @heartbeat_check_interval)
  end

  defp notify(%{session_pid: pid}, event) when is_pid(pid) do
    send(pid, {:meeting_bot_event, event})
  end

  defp notify(_, _), do: :ok

  defp get_participant_name(state, user_id) do
    case Map.get(state.participants, user_id) do
      %{display_name: name} -> name
      _ -> ""
    end
  end

  defp attempt_reconnect(state) do
    notify(state, {:bot_disconnected, %{reason: :connection_lost}})
    attempt = state.reconnect_attempts + 1

    if attempt <= @max_reconnect_attempts do
      delay = @initial_reconnect_delay * Integer.pow(2, attempt - 1)
      delay = min(delay, 30_000)
      Logger.info("[MeetingBot] Connection lost, reconnecting in #{delay}ms (attempt #{attempt})")
      timer = Process.send_after(self(), :retry_reconnect, delay)

      {:noreply,
       %{
         state
         | status: :reconnecting,
           reconnect_attempts: attempt,
           reconnect_timer: timer
       }}
    else
      notify(state, {:meeting_ended, %{reason: :connection_lost}})
      {:stop, :normal, %{state | status: :ended}}
    end
  end

  defp end_reason_atom(7), do: :kicked_by_host
  defp end_reason_atom(8), do: :ended_by_host
  defp end_reason_atom(9), do: :ended_by_host_for_another
  defp end_reason_atom(10), do: :free_meeting_timeout
  defp end_reason_atom(15), do: :ended_by_none
  defp end_reason_atom(16), do: :ended_by_admin
  defp end_reason_atom(17), do: :duplicate_session
  defp end_reason_atom(_), do: :ended

  defp maybe_update_field(struct, _field, nil), do: struct
  defp maybe_update_field(struct, field, value), do: Map.put(struct, field, value)
end
