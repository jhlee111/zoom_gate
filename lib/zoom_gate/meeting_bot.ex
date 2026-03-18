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
  @attribute_tracked_fields [:muted, :video_on, :is_cohost, :is_host]

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
    :reconnect_opts,
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

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def rename(pid, user_id, old_name, new_name),
    do: GenServer.call(pid, {:rename, user_id, old_name, new_name})

  def send_chat(pid, dest_node_id, text),
    do: GenServer.call(pid, {:chat, dest_node_id, text})

  def expel(pid, user_id), do: GenServer.call(pid, {:expel, user_id})
  def put_on_hold(pid, user_id, hold), do: GenServer.call(pid, {:put_on_hold, user_id, hold})
  def admit_all(pid), do: GenServer.call(pid, :admit_all)
  def mute(pid, user_id, muted), do: GenServer.call(pid, {:mute, user_id, muted})
  def start_recording(pid), do: GenServer.call(pid, :start_recording)
  def stop_recording(pid), do: GenServer.call(pid, :stop_recording)
  def lock_sharing(pid, locked), do: GenServer.call(pid, {:lock_sharing, locked})

  def spotlight(pid, user_id, spotlight),
    do: GenServer.call(pid, {:spotlight, user_id, spotlight})

  def end_meeting(pid), do: GenServer.call(pid, :end_meeting)
  def leave(pid), do: GenServer.call(pid, :leave)

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

  # -- GenServer Init --

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

  # -- Connection Lifecycle --

  @impl true
  def handle_continue(:connect, state) do
    case Connection.connect(%{state | status: :connecting}) do
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
    extra_params = extract_reconnect_params(state)

    case attempt_connection(%{state | status: :connecting}, extra_params) do
      {:ok, conn, stream, rwg_info, cookies} ->
        schedule_keepalive()
        schedule_heartbeat_check()

        {:noreply,
         %{
           state
           | conn: conn,
             stream: stream,
             rwg_info: rwg_info,
             cookies: cookies,
             last_heartbeat_at: System.monotonic_time(:millisecond),
             status: :connecting,
             reconnect_attempts: 0
         }}

      {:error, reason} ->
        handle_reconnect_failure(state, reason)
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
    {:reply, :ok, send_evt(state, Proto.evt_expel_req(), %{id: user_id})}
  end

  @impl true
  def handle_call({:put_on_hold, user_id, hold}, _from, state) do
    {:reply, :ok, send_evt(state, Proto.evt_put_on_hold_req(), %{id: user_id, bHold: hold})}
  end

  @impl true
  def handle_call(:admit_all, _from, state) do
    {:reply, :ok, send_evt(state, Proto.evt_admit_all_req(), %{})}
  end

  @impl true
  def handle_call({:mute, user_id, muted}, _from, state) do
    {:reply, :ok, send_evt(state, Proto.evt_mute_req(), %{id: user_id, mute: muted})}
  end

  @impl true
  def handle_call(:start_recording, _from, state) do
    {:reply, :ok, send_evt(state, Proto.evt_record_req(), %{bRecord: true, bPause: false})}
  end

  @impl true
  def handle_call(:stop_recording, _from, state) do
    {:reply, :ok, send_evt(state, Proto.evt_record_req(), %{bRecord: false, bPause: false})}
  end

  @impl true
  def handle_call({:lock_sharing, locked}, _from, state) do
    {:reply, :ok,
     send_evt(state, Proto.evt_lock_sharing_req(), %{lockShare: bool_to_int(locked)})}
  end

  @impl true
  def handle_call({:spotlight, user_id, spotlight}, _from, state) do
    {:reply, :ok,
     send_evt(state, Proto.evt_spotlight_req(), %{id: user_id, bSpotlight: spotlight})}
  end

  @impl true
  def handle_call(:end_meeting, _from, state) do
    {:reply, :ok, send_evt(state, Proto.evt_end_req(), %{})}
  end

  @impl true
  def handle_call(:leave, _from, state) do
    {:reply, :ok, send_evt(state, Proto.evt_leave_req(), %{})}
  end

  @impl true
  def handle_call(:get_participants, _from, state) do
    participants =
      Map.new(state.participants, fn {id, p} -> {id, Participant.to_event_map(p)} end)

    {:reply, participants, state}
  end

  @impl true
  def handle_call(:get_health, _from, state) do
    health = %{
      status: state.status,
      last_heartbeat_at: state.last_heartbeat_at,
      heartbeat_age_ms: heartbeat_age(state.last_heartbeat_at),
      reconnect_attempts: state.reconnect_attempts,
      participant_count: map_size(state.participants)
    }

    {:reply, health, state}
  end

  # -- Incoming WebSocket: Text --

  @impl true
  def handle_info({:gun_ws, _conn, _stream, {:text, data}}, state) do
    tap_analyzer(state, :incoming, data)

    with {:ok, msg} <- Protocol.decode(data) do
      {:noreply, handle_zoom_message(msg, state)}
    else
      _ ->
        Logger.warning("[MeetingBot] Unparseable message: #{data}")
        {:noreply, state}
    end
  end

  # -- Incoming WebSocket: Binary --

  @impl true
  def handle_info({:gun_ws, _conn, _stream, {:binary, data}}, state) do
    tap_analyzer(state, :incoming, {:binary, data})
    handle_binary_frame(Frame.decode(data), state)
  end

  # -- Incoming WebSocket: Close (already ended) --

  @impl true
  def handle_info({:gun_ws, _, _, {:close, code, reason}}, %{status: :ended} = state) do
    Logger.info("[MeetingBot] WebSocket closed: #{code} #{reason}")
    notify(state, {:meeting_ended, %{reason: :ws_closed}})
    {:stop, :normal, state}
  end

  # -- Incoming WebSocket: Close (unexpected) --

  @impl true
  def handle_info({:gun_ws, _, _, {:close, code, reason}}, state) do
    Logger.info("[MeetingBot] WebSocket closed: #{code} #{reason}")
    attempt_reconnect(state)
  end

  # -- Connection down (already ended) --

  @impl true
  def handle_info({:gun_down, _, _, reason, _}, %{status: :ended} = state) do
    Logger.error("[MeetingBot] Connection down: #{inspect(reason)}")
    {:stop, {:connection_down, reason}, state}
  end

  # -- Connection down (unexpected) --

  @impl true
  def handle_info({:gun_down, _, _, reason, _}, state) do
    Logger.error("[MeetingBot] Connection down: #{inspect(reason)}")
    attempt_reconnect(state)
  end

  # -- Timers --

  @impl true
  def handle_info(:keepalive, state) do
    schedule_keepalive()
    {:noreply, send_evt(state, Proto.evt_keepalive(), nil)}
  end

  @impl true
  def handle_info(:retry_reconnect, state) do
    {:noreply, state, {:continue, :reconnect}}
  end

  @impl true
  def handle_info(:trigger_reconnect, state) do
    attempt_reconnect(state)
  end

  # -- Heartbeat: active with timeout --

  @impl true
  def handle_info(:heartbeat_check, %{status: :active, last_heartbeat_at: last} = state)
      when is_integer(last) do
    elapsed = System.monotonic_time(:millisecond) - last
    handle_heartbeat_elapsed(state, elapsed)
  end

  # -- Heartbeat: not active or no heartbeat yet --

  @impl true
  def handle_info(:heartbeat_check, state) do
    schedule_heartbeat_check()
    {:noreply, state}
  end

  # -- Catch-all --

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[MeetingBot] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # -- Zoom Message Handlers --

  # Heartbeat (keepalive)
  defp handle_zoom_message(%{"evt" => Proto.evt_keepalive()} = msg, state) do
    Logger.debug("[MeetingBot] Heartbeat seq=#{msg["seq"]}")
    %{state | last_heartbeat_at: System.monotonic_time(:millisecond)}
  end

  # Join rejected (non-zero res)
  defp handle_zoom_message(%{"evt" => Proto.evt_join_res(), "body" => %{"res" => res}}, state)
       when is_integer(res) and res != 0 do
    Logger.error("[MeetingBot] Join rejected: res=#{res}")
    notify(state, {:error, %{message: "Join rejected", code: res}})
    %{state | status: :ended}
  end

  # Join success
  defp handle_zoom_message(%{"evt" => Proto.evt_join_res(), "body" => body}, state) do
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

  # Roster update
  defp handle_zoom_message(%{"evt" => Proto.evt_roster(), "body" => body}, state) do
    {participants, events} = Participant.merge_roster(state.participants, body)
    Enum.each(events, &notify(state, &1))
    %{state | participants: participants}
  end

  # Hold change
  defp handle_zoom_message(
         %{
           "evt" => Proto.evt_hold_change(),
           "body" => %{"id" => user_id, "bHold" => b_hold} = body
         },
         state
       ) do
    state = update_participant_hold(state, user_id, b_hold)
    bot_id = state.join_info["participantID"]
    handle_hold_change(state, user_id, b_hold, bot_id, body)
  end

  # Chat indication
  defp handle_zoom_message(%{"evt" => Proto.evt_chat_indication(), "body" => body}, state) do
    text = decode_chat_text(body)
    notify(state, {:chat_received, %{from_user_id: body["senderSN"], message: text}})
    state
  end

  # End: reconnect signal (reason=5)
  defp handle_zoom_message(%{"evt" => Proto.evt_end(), "body" => %{"reason" => 5} = body}, state) do
    Logger.info("[MeetingBot] Reconnect signal (reason=5, subReason=#{body["subReason"]})")
    send(self(), :trigger_reconnect)
    %{state | status: :reconnecting}
  end

  # End: with body
  defp handle_zoom_message(%{"evt" => Proto.evt_end(), "body" => body}, state) do
    reason = body["reason"] || 0
    reason_atom = end_reason_atom(reason)
    Logger.info("[MeetingBot] Meeting ended: #{reason_atom} (reason=#{reason})")
    notify(state, {:meeting_ended, %{reason: reason_atom, code: reason}})
    %{state | status: :ended}
  end

  # End: no body
  defp handle_zoom_message(%{"evt" => Proto.evt_end()}, state) do
    Logger.info("[MeetingBot] Meeting ended (no body)")
    notify(state, {:meeting_ended, %{reason: :ended}})
    %{state | status: :ended}
  end

  # Host change
  defp handle_zoom_message(%{"evt" => Proto.evt_host_change(), "body" => body}, state) do
    Logger.info("[MeetingBot] Host changed to #{body["id"]}")
    notify(state, {:host_changed, %{new_host_id: body["id"]}})
    state
  end

  # Attribute change
  defp handle_zoom_message(
         %{"evt" => Proto.evt_attribute(), "body" => %{"id" => user_id} = body},
         state
       ) do
    case Map.fetch(state.participants, user_id) do
      {:ok, participant} ->
        updated = apply_attribute_changes(participant, body)
        notify_attribute_diff(state, user_id, participant, updated)
        %{state | participants: Map.put(state.participants, user_id, updated)}

      :error ->
        notify(state, {:attribute_changed, %{zoom_user_id: user_id, changes: body}})
        state
    end
  end

  # Meeting option change
  defp handle_zoom_message(%{"evt" => Proto.evt_option(), "body" => body}, state) do
    notify(state, {:meeting_option_changed, body})
    state
  end

  # Catch-all: known evt with body
  defp handle_zoom_message(%{"evt" => evt, "body" => body}, state) do
    notify(state, {:raw_event, %{evt: evt, body: body}})
    state
  end

  # Catch-all: evt without body
  defp handle_zoom_message(%{"evt" => evt}, state) do
    notify(state, {:raw_event, %{evt: evt, body: nil}})
    state
  end

  # -- Binary Frame Handlers --

  defp handle_binary_frame({:data, json, server_seq}, state) do
    state = %{state | last_recv_seq: max(state.last_recv_seq, server_seq)}

    with {:ok, msg} <- Protocol.decode(json) do
      {:noreply, handle_zoom_message(msg, state)}
    else
      _ ->
        Logger.debug("[MeetingBot] Binary frame non-JSON payload")
        {:noreply, state}
    end
  end

  defp handle_binary_frame({:handshake, _frame}, state) do
    Logger.info("[MeetingBot] Received server handshake")
    {:noreply, state}
  end

  defp handle_binary_frame({:ping, frame}, state) do
    :gun.ws_send(state.conn, state.stream, {:binary, Frame.encode_pong(frame)})
    {:noreply, state}
  end

  defp handle_binary_frame({:data_binary, _payload, server_seq}, state) do
    {:noreply, %{state | last_recv_seq: max(state.last_recv_seq, server_seq)}}
  end

  defp handle_binary_frame({:pong, _}, state), do: {:noreply, state}

  defp handle_binary_frame({:unknown, type}, state) do
    Logger.debug("[MeetingBot] Unknown binary frame type=0x#{Integer.to_string(type, 16)}")
    {:noreply, state}
  end

  # -- Hold Change Dispatch --

  # Bot put on hold
  defp handle_hold_change(state, bot_id, true, bot_id, body) do
    Logger.info("[MeetingBot] Bot put in waiting room")
    %{state | status: :waiting_room, reconnect_opts: body}
  end

  # Other user put on hold
  defp handle_hold_change(state, user_id, true, _bot_id, _body) do
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

  # Bot admitted from hold
  defp handle_hold_change(state, bot_id, false, bot_id, _body) do
    Logger.info("[MeetingBot] Bot admitted from waiting room — reconnecting")
    %{state | status: :reconnecting}
  end

  # Other user admitted from hold
  defp handle_hold_change(state, user_id, false, _bot_id, _body) do
    notify(state, {:waiting_room_leave, %{zoom_user_id: user_id}})
    state
  end

  # -- Send Event --

  defp send_evt(%{as_type: 2} = state, evt, body) do
    seq = state.seq + 1
    wire_seq = state.wire_seq + 1
    json = Protocol.encode(evt, body, seq)
    tap_analyzer(state, :outgoing, json)
    frame = Frame.encode_data(json, wire_seq, monotonic_timestamp(), state.last_recv_seq)
    :gun.ws_send(state.conn, state.stream, {:binary, frame})
    %{state | seq: seq, wire_seq: wire_seq}
  end

  defp send_evt(state, evt, body) do
    seq = state.seq + 1
    json = Protocol.encode(evt, body, seq)
    tap_analyzer(state, :outgoing, json)
    :gun.ws_send(state.conn, state.stream, {:text, json})
    %{state | seq: seq}
  end

  # -- Reconnection Helpers --

  defp extract_reconnect_params(%{reconnect_opts: opts}) when is_map(opts) do
    opts |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end) |> Map.new()
  end

  defp extract_reconnect_params(%{reconnect_opts: opts}) when is_list(opts) do
    opts |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end) |> Map.new()
  end

  defp extract_reconnect_params(_), do: %{}

  # Quick reconnect (have meeting_info + rwg_info)
  defp attempt_connection(%{meeting_info: mi, rwg_info: ri, cookies: cookies} = state, extra)
       when not is_nil(mi) and not is_nil(ri) do
    case Connection.reconnect(state, mi, ri, cookies, extra) do
      {:ok, conn, stream} -> {:ok, conn, stream, ri, cookies}
      error -> error
    end
  end

  # Full connect from scratch
  defp attempt_connection(state, _extra) do
    case Connection.connect(state) do
      {:ok, conn, stream, _mi, rwg_info, cookies} -> {:ok, conn, stream, rwg_info, cookies}
      error -> error
    end
  end

  defp handle_reconnect_failure(state, reason) do
    Logger.error("[MeetingBot] Reconnection failed: #{inspect(reason)}")
    next_attempt = state.reconnect_attempts + 1
    schedule_or_stop_reconnect(state, reason, next_attempt)
  end

  defp schedule_or_stop_reconnect(state, _reason, attempt)
       when attempt < @max_reconnect_attempts do
    delay = min(@initial_reconnect_delay * Integer.pow(2, attempt - 1), 30_000)
    Logger.info("[MeetingBot] Retrying in #{delay}ms (attempt #{attempt})")
    timer = Process.send_after(self(), :retry_reconnect, delay)

    {:noreply,
     %{state | status: :reconnecting, reconnect_attempts: attempt, reconnect_timer: timer}}
  end

  defp schedule_or_stop_reconnect(state, reason, attempt) do
    notify(state, {:error, %{message: "Reconnection failed after #{attempt} attempts"}})
    {:stop, {:reconnection_failed, reason}, state}
  end

  defp attempt_reconnect(state) do
    notify(state, {:bot_disconnected, %{reason: :connection_lost}})
    next_attempt = state.reconnect_attempts + 1
    do_attempt_reconnect(state, next_attempt)
  end

  defp do_attempt_reconnect(state, attempt) when attempt <= @max_reconnect_attempts do
    delay = min(@initial_reconnect_delay * Integer.pow(2, attempt - 1), 30_000)
    Logger.info("[MeetingBot] Connection lost, reconnecting in #{delay}ms (attempt #{attempt})")
    timer = Process.send_after(self(), :retry_reconnect, delay)

    {:noreply,
     %{state | status: :reconnecting, reconnect_attempts: attempt, reconnect_timer: timer}}
  end

  defp do_attempt_reconnect(state, _attempt) do
    notify(state, {:meeting_ended, %{reason: :connection_lost}})
    {:stop, :normal, %{state | status: :ended}}
  end

  # -- Heartbeat --

  defp handle_heartbeat_elapsed(state, elapsed) when elapsed > @heartbeat_timeout do
    Logger.warning("[MeetingBot] Heartbeat timeout (#{elapsed}ms), triggering reconnect")
    attempt_reconnect(state)
  end

  defp handle_heartbeat_elapsed(state, _elapsed) do
    schedule_heartbeat_check()
    {:noreply, state}
  end

  defp heartbeat_age(nil), do: nil
  defp heartbeat_age(last_at), do: System.monotonic_time(:millisecond) - last_at

  # -- Attribute Change Helpers --

  defp apply_attribute_changes(participant, body) do
    participant
    |> maybe_update_field(:muted, body["muted"])
    |> maybe_update_field(:video_on, body["bVideoOn"])
    |> maybe_update_field(:is_cohost, body["isCoHost"])
    |> maybe_update_field(:is_cohost, body["bCoHost"])
    |> maybe_update_field(:is_host, body["isHost"])
  end

  defp notify_attribute_diff(state, user_id, old, new) do
    changes =
      @attribute_tracked_fields
      |> Enum.filter(fn field -> Map.get(old, field) != Map.get(new, field) end)
      |> Map.new(fn field -> {field, Map.get(new, field)} end)

    case map_size(changes) do
      0 -> :ok
      _ -> notify(state, {:participant_updated, Map.merge(%{zoom_user_id: user_id}, changes)})
    end
  end

  # -- Participant Helpers --

  defp update_participant_hold(%{participants: ps} = state, user_id, b_hold) do
    case Map.fetch(ps, user_id) do
      {:ok, participant} ->
        %{state | participants: Map.put(ps, user_id, %{participant | b_hold: b_hold})}

      :error ->
        state
    end
  end

  defp get_participant_name(%{participants: ps}, user_id) do
    case ps do
      %{^user_id => %{display_name: name}} -> name
      _ -> ""
    end
  end

  # -- Notification --

  defp notify(%{session_pid: pid}, event) when is_pid(pid),
    do: send(pid, {:meeting_bot_event, event})

  defp notify(_, _), do: :ok

  defp tap_analyzer(%{analyzer: pid}, direction, data) when is_pid(pid),
    do: send(pid, {:raw_ws, direction, data})

  defp tap_analyzer(_, _, _), do: :ok

  # -- Utilities --

  defp decode_chat_text(%{"text" => text}) when is_binary(text), do: Protocol.b64_decode(text)
  defp decode_chat_text(_), do: ""

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0

  defp monotonic_timestamp do
    System.monotonic_time(:millisecond) |> rem(0xFFFFFFFF) |> max(0)
  end

  defp schedule_keepalive, do: Process.send_after(self(), :keepalive, @keepalive_interval)

  defp schedule_heartbeat_check,
    do: Process.send_after(self(), :heartbeat_check, @heartbeat_check_interval)

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
