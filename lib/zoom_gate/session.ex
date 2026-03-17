defmodule ZoomGate.Session do
  @moduledoc """
  GenServer managing a single Zoom meeting bot session.

  Each session:
  1. Starts a MeetingBot GenServer (pure Elixir RWG WebSocket client)
  2. Receives events from MeetingBot via `{:meeting_bot_event, event}` messages
  3. Forwards events to subscribers, callbacks, and webhooks
  4. Translates API commands into MeetingBot calls

  ## Lifecycle

      Session.start_link(meeting_id: "123", sdk_key: "...", ...)
        → MeetingBot.start_link(...)
        → WebSocket connect → RWG join
        → monitoring waiting room
        → ...events flow...
        → meeting ends or leave called
        → MeetingBot terminates, Session terminates
  """

  use GenServer, restart: :temporary

  require Logger

  # -- Public API --

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    meeting_id = Keyword.fetch!(opts, :meeting_id)
    GenServer.start_link(__MODULE__, opts, name: via(meeting_id))
  end

  @doc """
  Registry-based name for cross-node addressing.

      GenServer.call({ZoomGate.Session.via("123"), :zoom_bridge@host}, {:admit, ...})
  """
  @spec via(String.t()) :: {:via, Registry, {ZoomGate.Registry, String.t()}}
  def via(meeting_id) do
    {:via, Registry, {ZoomGate.Registry, meeting_id}}
  end

  @doc "Returns the PID of the session for `meeting_id`, or `nil` if none exists."
  @spec whereis(String.t()) :: pid() | nil
  def whereis(meeting_id) do
    case Registry.lookup(ZoomGate.Registry, meeting_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Subscribe a process to receive `{:zoom_gate, {event_type, payload}}` messages."
  @spec subscribe(String.t(), pid()) :: :ok
  def subscribe(meeting_id, pid \\ self()) do
    GenServer.call(via(meeting_id), {:subscribe, pid})
  end

  @doc "Unsubscribe a process from session events."
  @spec unsubscribe(String.t(), pid()) :: :ok
  def unsubscribe(meeting_id, pid \\ self()) do
    GenServer.call(via(meeting_id), {:unsubscribe, pid})
  end

  @doc "Returns session status: meeting_id, status, participants, and waiting_room."
  @spec get_status(String.t()) :: map()
  def get_status(meeting_id) do
    GenServer.call(via(meeting_id), :get_status)
  end

  @doc "Admit a participant from the waiting room into the meeting."
  @spec admit(String.t(), non_neg_integer(), keyword()) :: :ok
  def admit(meeting_id, zoom_user_id, opts \\ []) do
    GenServer.call(via(meeting_id), {:admit, zoom_user_id, opts})
  end

  @doc "Deny a participant in the waiting room, removing them from the meeting."
  @spec deny(String.t(), non_neg_integer(), keyword()) :: :ok
  def deny(meeting_id, zoom_user_id, opts \\ []) do
    GenServer.call(via(meeting_id), {:deny, zoom_user_id, opts})
  end

  @doc "Rename a participant's display name."
  @spec rename(String.t(), non_neg_integer(), String.t()) :: :ok
  def rename(meeting_id, zoom_user_id, display_name) do
    GenServer.call(via(meeting_id), {:rename, zoom_user_id, display_name})
  end

  @doc "Expel a participant from the meeting."
  @spec expel(String.t(), non_neg_integer()) :: :ok
  def expel(meeting_id, zoom_user_id) do
    GenServer.call(via(meeting_id), {:expel, zoom_user_id})
  end

  @doc "Send a chat message. Use `to: zoom_user_id` in opts for a direct message."
  @spec send_chat(String.t(), String.t(), keyword()) :: :ok
  def send_chat(meeting_id, message, opts \\ []) do
    GenServer.call(via(meeting_id), {:send_chat, message, opts})
  end

  @doc "Sends a chat message to all participants in the waiting room (broadcast)."
  @spec chat_waiting_room(String.t(), String.t()) :: :ok
  def chat_waiting_room(meeting_id, message) do
    GenServer.call(via(meeting_id), {:chat_waiting_room, message})
  end

  @doc "Admit all participants currently in the waiting room."
  @spec admit_all(String.t()) :: :ok
  def admit_all(meeting_id) do
    GenServer.call(via(meeting_id), :admit_all)
  end

  @doc "Mute a participant's audio."
  @spec mute(String.t(), non_neg_integer()) :: :ok
  def mute(meeting_id, zoom_user_id) do
    GenServer.call(via(meeting_id), {:mute, zoom_user_id})
  end

  @doc "End the meeting for all participants."
  @spec end_meeting(String.t()) :: :ok
  def end_meeting(meeting_id) do
    GenServer.call(via(meeting_id), :end_meeting)
  end

  # -- GenServer Callbacks --

  @impl true
  def init(opts) do
    meeting_id = Keyword.fetch!(opts, :meeting_id)
    callback = Keyword.get(opts, :callback)
    webhook_url = Keyword.get(opts, :webhook_url)

    state = %{
      meeting_id: meeting_id,
      callback: callback,
      webhook_url: webhook_url,
      meeting_bot: nil,
      participants: %{},
      waiting_room: %{},
      subscribers: MapSet.new(),
      status: :initializing
    }

    {:ok, state, {:continue, {:start_meeting_bot, opts}}}
  end

  @impl true
  def handle_continue({:start_meeting_bot, opts}, state) do
    worker_mod = Application.get_env(:zoom_gate, :bot_module, ZoomGate.MeetingBot)

    sdk_key =
      Keyword.get(opts, :sdk_key) || Application.get_env(:zoom_gate, :zoom_sdk_key, "")

    sdk_secret =
      Keyword.get(opts, :sdk_secret) || Application.get_env(:zoom_gate, :zoom_sdk_secret, "")

    zak = Keyword.get(opts, :zak) || Application.get_env(:zoom_gate, :zoom_zak, "")

    meeting_bot_opts = [
      meeting_number: state.meeting_id,
      password: Keyword.get(opts, :meeting_password, ""),
      display_name: Keyword.get(opts, :display_name, "ZoomGate-Bot"),
      sdk_key: sdk_key,
      sdk_secret: sdk_secret,
      zak: zak,
      role: if(zak != "", do: 1, else: 0),
      as_type: Keyword.get(opts, :as_type, 1),
      session_pid: self()
    ]

    # Use GenServer.start (not start_link) to avoid linking — Session monitors
    # the MeetingBot independently, so a :kill signal won't propagate.
    case GenServer.start(worker_mod, meeting_bot_opts) do
      {:ok, pid} ->
        Process.monitor(pid)
        Logger.info("[ZoomGate] Session #{state.meeting_id}: MeetingBot started")
        {:noreply, %{state | meeting_bot: pid, status: :connecting}}

      {:error, reason} ->
        Logger.error(
          "[ZoomGate] Session #{state.meeting_id}: MeetingBot start failed: #{inspect(reason)}"
        )

        {:stop, {:meeting_bot_failed, reason}, state}
    end
  end

  # -- Subscribe / Unsubscribe --

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      meeting_id: state.meeting_id,
      status: state.status,
      participants: state.participants,
      waiting_room: state.waiting_room
    }

    {:reply, status, state}
  end

  # -- Commands --

  @impl true
  def handle_call({:admit, zoom_user_id, _opts}, _from, state) do
    worker_mod(state).put_on_hold(state.meeting_bot, zoom_user_id, false)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:deny, zoom_user_id, _opts}, _from, state) do
    worker_mod(state).expel(state.meeting_bot, zoom_user_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:rename, zoom_user_id, display_name}, _from, state) do
    old_name = get_participant_name(state, zoom_user_id)
    worker_mod(state).rename(state.meeting_bot, zoom_user_id, old_name, display_name)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:expel, zoom_user_id}, _from, state) do
    worker_mod(state).expel(state.meeting_bot, zoom_user_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:send_chat, message, opts}, _from, state) do
    to = Keyword.get(opts, :to, 0)
    worker_mod(state).send_chat(state.meeting_bot, to, message)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:chat_waiting_room, message}, _from, state) do
    # destNodeID=4 targets SilentModeUsers (waiting room participants)
    # Note: waiting room chat is NOT encrypted (just base64)
    worker_mod(state).send_chat(state.meeting_bot, 4, message)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:admit_all, _from, state) do
    worker_mod(state).admit_all(state.meeting_bot)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:mute, zoom_user_id}, _from, state) do
    worker_mod(state).mute(state.meeting_bot, zoom_user_id, true)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:end_meeting, _from, state) do
    worker_mod(state).end_meeting(state.meeting_bot)
    {:reply, :ok, state}
  end

  # -- MeetingBot Events --

  @impl true
  def handle_info({:meeting_bot_event, {:joined, _join_info}}, state) do
    Logger.info("[ZoomGate] Session #{state.meeting_id}: bot joined meeting")
    deliver_event(state, {:bot_joined, %{meeting_id: state.meeting_id}})
    {:noreply, %{state | status: :active}}
  end

  @impl true
  def handle_info({:meeting_bot_event, {:participant_joined, participant}}, state) do
    deliver_event(state, {:participant_joined, participant})
    participants = Map.put(state.participants, participant.zoom_user_id, participant)
    {:noreply, %{state | participants: participants}}
  end

  @impl true
  def handle_info({:meeting_bot_event, {:participant_left, %{zoom_user_id: uid}}}, state) do
    deliver_event(state, {:participant_left, %{zoom_user_id: uid}})
    participants = Map.delete(state.participants, uid)
    {:noreply, %{state | participants: participants}}
  end

  @impl true
  def handle_info({:meeting_bot_event, {:waiting_room_join, participant}}, state) do
    deliver_event(state, {:waiting_room_join, participant})
    waiting_room = Map.put(state.waiting_room, participant.zoom_user_id, participant)
    {:noreply, %{state | waiting_room: waiting_room}}
  end

  @impl true
  def handle_info({:meeting_bot_event, {:waiting_room_leave, %{zoom_user_id: uid}}}, state) do
    deliver_event(state, {:waiting_room_leave, %{zoom_user_id: uid}})
    waiting_room = Map.delete(state.waiting_room, uid)
    {:noreply, %{state | waiting_room: waiting_room}}
  end

  @impl true
  def handle_info({:meeting_bot_event, {:participant_renamed, payload}}, state) do
    deliver_event(state, {:participant_renamed, payload})
    # Update display_name in local state
    uid = payload.zoom_user_id
    state = update_participant_name(state, uid, payload.new_name)
    {:noreply, state}
  end

  @impl true
  def handle_info({:meeting_bot_event, {:chat_received, payload}}, state) do
    deliver_event(state, {:chat_received, payload})
    {:noreply, state}
  end

  @impl true
  def handle_info({:meeting_bot_event, {:host_changed, payload}}, state) do
    deliver_event(state, {:host_changed, payload})
    {:noreply, state}
  end

  @impl true
  def handle_info({:meeting_bot_event, {:meeting_ended, payload}}, state) do
    Logger.info(
      "[ZoomGate] Session #{state.meeting_id}: meeting ended (#{inspect(payload.reason)})"
    )

    deliver_event(state, {:meeting_ended, payload})
    {:stop, :normal, %{state | status: :ended}}
  end

  @impl true
  def handle_info({:meeting_bot_event, {:error, payload}}, state) do
    Logger.error("[ZoomGate] Session #{state.meeting_id}: error: #{inspect(payload)}")
    deliver_event(state, {:error, payload})
    {:noreply, state}
  end

  # MeetingBot process died
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{meeting_bot: pid} = state) do
    Logger.warning(
      "[ZoomGate] Session #{state.meeting_id}: MeetingBot exited: #{inspect(reason)}"
    )

    deliver_event(state, {:meeting_ended, %{reason: :worker_exit}})
    {:stop, {:meeting_bot_exited, reason}, %{state | meeting_bot: nil, status: :terminated}}
  end

  # Subscriber process died
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def terminate(reason, state) do
    if state.meeting_bot && Process.alive?(state.meeting_bot) do
      try do
        worker_mod(state).leave(state.meeting_bot)
      catch
        _, _ -> :ok
      end
    end

    Logger.info("[ZoomGate] Session #{state.meeting_id}: terminated (#{inspect(reason)})")
  end

  # -- Internal --

  defp deliver_event(state, event) do
    deliver_to_callback(state.callback, event)
    deliver_to_webhook(state.webhook_url, event)

    Phoenix.PubSub.broadcast(
      ZoomGate.PubSub,
      "zoom_gate:#{state.meeting_id}",
      {:zoom_gate, event}
    )

    for pid <- state.subscribers do
      send(pid, {:zoom_gate, event})
    end

    :ok
  end

  defp deliver_to_callback(nil, _event), do: :ok

  defp deliver_to_callback(pid, event) when is_pid(pid) do
    send(pid, {:zoom_gate, event})
  end

  defp deliver_to_callback({mod, fun}, event) do
    apply(mod, fun, [event])
  end

  defp deliver_to_callback(_, _), do: :ok

  defp deliver_to_webhook(nil, _event), do: :ok

  defp deliver_to_webhook(url, event) when is_binary(url) do
    Task.start(fn ->
      {event_type, payload} = event

      body =
        Jason.encode!(%{
          event: event_type,
          data: payload,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      case :httpc.request(
             :post,
             {String.to_charlist(url), [], ~c"application/json", body},
             [],
             []
           ) do
        {:ok, {{_, status, _}, _, _}} when status in 200..299 -> :ok
        other -> Logger.warning("[ZoomGate] Webhook delivery failed: #{inspect(other)}")
      end
    end)
  end

  defp deliver_to_webhook(_, _), do: :ok

  defp get_participant_name(state, zoom_user_id) do
    case Map.get(state.participants, zoom_user_id) || Map.get(state.waiting_room, zoom_user_id) do
      %{display_name: name} -> name
      _ -> ""
    end
  end

  defp update_participant_name(state, uid, new_name) do
    cond do
      Map.has_key?(state.participants, uid) ->
        p = Map.update!(state.participants[uid], :display_name, fn _ -> new_name end)
        %{state | participants: Map.put(state.participants, uid, p)}

      Map.has_key?(state.waiting_room, uid) ->
        p = Map.update!(state.waiting_room[uid], :display_name, fn _ -> new_name end)
        %{state | waiting_room: Map.put(state.waiting_room, uid, p)}

      true ->
        state
    end
  end

  defp worker_mod(_state) do
    Application.get_env(:zoom_gate, :bot_module, ZoomGate.MeetingBot)
  end
end
