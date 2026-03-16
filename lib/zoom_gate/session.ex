defmodule ZoomGate.Session do
  @moduledoc """
  GenServer managing a single Zoom meeting bot session.

  Each session:
  1. Opens a Port to the C++ SDK worker binary
  2. Sends commands (admit, deny, rename, expel, chat) via stdin
  3. Receives SDK events (waiting_room_join, participant_left) via stdout
  4. Forwards events to the registered callback (PID, MFA, or webhook URL)

  ## Lifecycle

      Session.start_link(meeting_id: "123", sdk_key: "...", ...)
        → Port.open(zoom_worker)
        → SDK init + join meeting
        → monitoring waiting room
        → ...events flow...
        → meeting ends or leave_meeting called
        → Port closes, GenServer terminates
  """

  use GenServer, restart: :temporary

  require Logger

  @worker_binary "zoom_worker"

  # -- Public API --

  def start_link(opts) do
    meeting_id = Keyword.fetch!(opts, :meeting_id)
    GenServer.start_link(__MODULE__, opts, name: via(meeting_id))
  end

  @doc """
  Registry-based name for cross-node addressing.

      GenServer.call({ZoomGate.Session.via("123"), :zoom_bridge@host}, {:admit, ...})
  """
  def via(meeting_id) do
    {:via, Registry, {ZoomGate.Registry, meeting_id}}
  end

  def whereis(meeting_id) do
    case Registry.lookup(ZoomGate.Registry, meeting_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def admit(meeting_id, zoom_user_id, opts \\ []) do
    GenServer.call(via(meeting_id), {:admit, zoom_user_id, opts})
  end

  def deny(meeting_id, zoom_user_id, opts \\ []) do
    GenServer.call(via(meeting_id), {:deny, zoom_user_id, opts})
  end

  def rename(meeting_id, zoom_user_id, display_name) do
    GenServer.call(via(meeting_id), {:rename, zoom_user_id, display_name})
  end

  def expel(meeting_id, zoom_user_id) do
    GenServer.call(via(meeting_id), {:expel, zoom_user_id})
  end

  def send_chat(meeting_id, message, opts \\ []) do
    GenServer.call(via(meeting_id), {:send_chat, message, opts})
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
      port: nil,
      port_buffer: "",
      participants: %{},
      waiting_room: %{},
      status: :initializing
    }

    {:ok, state, {:continue, {:start_worker, opts}}}
  end

  @impl true
  def handle_continue({:start_worker, opts}, state) do
    worker_path = worker_executable_path()

    args = build_worker_args(opts)

    port =
      Port.open({:spawn_executable, worker_path}, [
        :binary,
        :exit_status,
        :use_stdio,
        {:args, args},
        {:line, 4096}
      ])

    Logger.info("[ZoomGate] Session #{state.meeting_id}: worker started")
    {:noreply, %{state | port: port, status: :connecting}}
  end

  @impl true
  def handle_call({:admit, zoom_user_id, opts}, _from, state) do
    display_name = Keyword.get(opts, :display_name)

    cmd = %{command: "admit", zoom_user_id: zoom_user_id}
    cmd = if display_name, do: Map.put(cmd, :display_name, display_name), else: cmd

    send_to_worker(state.port, cmd)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:deny, zoom_user_id, opts}, _from, state) do
    message = Keyword.get(opts, :message)

    cmd = %{command: "deny", zoom_user_id: zoom_user_id}
    cmd = if message, do: Map.put(cmd, :message, message), else: cmd

    send_to_worker(state.port, cmd)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:rename, zoom_user_id, display_name}, _from, state) do
    send_to_worker(state.port, %{
      command: "rename",
      zoom_user_id: zoom_user_id,
      display_name: display_name
    })

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:expel, zoom_user_id}, _from, state) do
    send_to_worker(state.port, %{command: "expel", zoom_user_id: zoom_user_id})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:send_chat, message, opts}, _from, state) do
    to = Keyword.get(opts, :to)

    cmd = %{command: "chat", message: message}
    cmd = if to, do: Map.put(cmd, :to, to), else: cmd

    send_to_worker(state.port, cmd)
    {:reply, :ok, state}
  end

  # Port messages (SDK events from C++ worker)
  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    case Jason.decode(line) do
      {:ok, event} ->
        state = handle_sdk_event(event, state)
        {:noreply, state}

      {:error, _} ->
        Logger.warning("[ZoomGate] Session #{state.meeting_id}: unparseable worker output: #{line}")
        {:noreply, state}
    end
  end

  # Worker process exited
  @impl true
  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.warning("[ZoomGate] Session #{state.meeting_id}: worker exited with code #{code}")
    deliver_event(state, {:meeting_ended, %{reason: :worker_exit, exit_code: code}})
    {:stop, {:worker_exited, code}, %{state | port: nil, status: :terminated}}
  end

  @impl true
  def terminate(reason, state) do
    if state.port do
      send_to_worker(state.port, %{command: "leave"})
      Port.close(state.port)
    end

    Logger.info("[ZoomGate] Session #{state.meeting_id}: terminated (#{inspect(reason)})")
  end

  # -- Internal --

  defp handle_sdk_event(%{"event" => "joined"}, state) do
    Logger.info("[ZoomGate] Session #{state.meeting_id}: bot joined meeting")
    deliver_event(state, {:bot_joined, %{meeting_id: state.meeting_id}})
    %{state | status: :active}
  end

  defp handle_sdk_event(%{"event" => "waiting_room_join"} = data, state) do
    participant = %{
      zoom_user_id: data["zoom_user_id"],
      display_name: data["display_name"],
      email: data["email"]
    }

    deliver_event(state, {:waiting_room_join, participant})

    waiting_room = Map.put(state.waiting_room, data["zoom_user_id"], participant)
    %{state | waiting_room: waiting_room}
  end

  defp handle_sdk_event(%{"event" => "waiting_room_leave"} = data, state) do
    deliver_event(state, {:waiting_room_leave, %{zoom_user_id: data["zoom_user_id"]}})

    waiting_room = Map.delete(state.waiting_room, data["zoom_user_id"])
    %{state | waiting_room: waiting_room}
  end

  defp handle_sdk_event(%{"event" => "participant_joined"} = data, state) do
    participant = %{
      zoom_user_id: data["zoom_user_id"],
      display_name: data["display_name"]
    }

    deliver_event(state, {:participant_joined, participant})

    participants = Map.put(state.participants, data["zoom_user_id"], participant)
    %{state | participants: participants}
  end

  defp handle_sdk_event(%{"event" => "participant_left"} = data, state) do
    deliver_event(state, {:participant_left, %{zoom_user_id: data["zoom_user_id"]}})

    participants = Map.delete(state.participants, data["zoom_user_id"])
    %{state | participants: participants}
  end

  defp handle_sdk_event(%{"event" => "meeting_ended"}, state) do
    Logger.info("[ZoomGate] Session #{state.meeting_id}: meeting ended")
    deliver_event(state, {:meeting_ended, %{reason: :host_ended}})
    %{state | status: :ended}
  end

  defp handle_sdk_event(%{"event" => "error"} = data, state) do
    Logger.error("[ZoomGate] Session #{state.meeting_id}: SDK error: #{data["message"]}")
    deliver_event(state, {:error, %{message: data["message"], code: data["code"]}})
    state
  end

  defp handle_sdk_event(unknown, state) do
    Logger.debug("[ZoomGate] Session #{state.meeting_id}: unknown event: #{inspect(unknown)}")
    state
  end

  defp deliver_event(%{callback: nil, webhook_url: nil}, _event), do: :ok

  defp deliver_event(%{callback: pid}, event) when is_pid(pid) do
    send(pid, {:zoom_gate, event})
  end

  defp deliver_event(%{callback: {mod, fun}}, event) do
    apply(mod, fun, [event])
  end

  defp deliver_event(%{webhook_url: url}, event) when is_binary(url) do
    # Webhook delivery is fire-and-forget; failures are logged
    Task.start(fn ->
      {event_type, payload} = event

      body =
        Jason.encode!(%{
          event: event_type,
          data: payload,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      case :httpc.request(:post, {String.to_charlist(url), [], ~c"application/json", body}, [], []) do
        {:ok, {{_, status, _}, _, _}} when status in 200..299 -> :ok
        other -> Logger.warning("[ZoomGate] Webhook delivery failed: #{inspect(other)}")
      end
    end)
  end

  defp deliver_event(_, _), do: :ok

  defp send_to_worker(port, command) do
    json = Jason.encode!(command)
    Port.command(port, json <> "\n")
  end

  defp worker_executable_path do
    Application.get_env(:zoom_gate, :worker_path, @worker_binary)
  end

  defp build_worker_args(opts) do
    meeting_id = Keyword.fetch!(opts, :meeting_id)
    sdk_key = Keyword.get(opts, :sdk_key, "")
    sdk_secret = Keyword.get(opts, :sdk_secret, "")
    password = Keyword.get(opts, :meeting_password, "")

    [meeting_id, sdk_key, sdk_secret, password]
  end
end
