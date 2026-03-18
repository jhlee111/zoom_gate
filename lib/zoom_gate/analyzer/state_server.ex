defmodule ZoomGate.Analyzer.StateServer do
  @moduledoc """
  Observable GenServer that maintains complete Zoom client state.

  Composes ClientState (pure reducer), Recorder (ETS log), and Correlator
  (command-response linking). Emits `:telemetry` events and PubSub broadcasts
  on every state change, making it fully observable.
  """

  use GenServer

  alias ZoomGate.Analyzer.{ClientState, Recorder, Correlator, EventDecoder}

  defstruct [
    :session_id,
    :client_state,
    subscribers: MapSet.new()
  ]

  # -- Public API --

  @doc "Start the analyzer state server for a session."
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    meeting_number = Keyword.get(opts, :meeting_number, "")
    GenServer.start_link(__MODULE__, {session_id, meeting_number}, name: via(session_id))
  end

  @doc "Inject a raw RWG event for processing."
  def inject_event(pid, direction, event, raw_data) do
    GenServer.cast(pid, {:inject_event, direction, event, raw_data})
  end

  @doc "Get current client state snapshot."
  def get_state(pid), do: GenServer.call(pid, :get_state)

  @doc "Get current participant map."
  def get_participants(pid), do: GenServer.call(pid, :get_participants)

  @doc "Get current meeting settings."
  def get_meeting_settings(pid), do: GenServer.call(pid, :get_meeting_settings)

  @doc "Get chat history."
  def get_chat_history(pid), do: GenServer.call(pid, :get_chat_history)

  @doc "Query recorded messages."
  def get_records(pid, opts \\ []), do: GenServer.call(pid, {:get_records, opts})

  @doc "Get unknown events seen."
  def get_unknowns(pid), do: GenServer.call(pid, :get_unknowns)

  @doc "Run correlator on recorded messages."
  def get_correlations(pid), do: GenServer.call(pid, :get_correlations)

  @doc "Subscribe to state change notifications."
  def subscribe(pid), do: GenServer.call(pid, {:subscribe, self()})

  # -- GenServer Callbacks --

  @impl true
  def init({session_id, meeting_number}) do
    Recorder.new(session_id)

    state = %__MODULE__{
      session_id: session_id,
      client_state: ClientState.new(meeting_number)
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:inject_event, direction, event, raw_data}, state) do
    # 1. Record the raw message
    {:ok, decoded} = EventDecoder.decode(raw_data)
    Recorder.record(state.session_id, direction, decoded, raw_data)

    # 2. Apply to ClientState
    {new_client_state, changes} = ClientState.apply_event(state.client_state, event)

    # 3. Emit telemetry for each change
    emit_telemetry(state.session_id, changes)

    # 4. Notify subscribers
    if changes != [] do
      notify_subscribers(state.subscribers, changes)
      broadcast_pubsub(state.session_id, changes)
    end

    {:noreply, %{state | client_state: new_client_state}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.client_state, state}
  end

  def handle_call(:get_participants, _from, state) do
    {:reply, state.client_state.participants, state}
  end

  def handle_call(:get_meeting_settings, _from, state) do
    {:reply, state.client_state.meeting_settings, state}
  end

  def handle_call(:get_chat_history, _from, state) do
    {:reply, state.client_state.chat_history, state}
  end

  def handle_call({:get_records, _opts}, _from, state) do
    {:reply, Recorder.get_all(state.session_id), state}
  end

  def handle_call(:get_unknowns, _from, state) do
    {:reply, Recorder.get_unknowns(state.session_id), state}
  end

  def handle_call(:get_correlations, _from, state) do
    records = Recorder.get_all(state.session_id)
    {:reply, Correlator.correlate(records), state}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def terminate(_reason, state) do
    Recorder.destroy(state.session_id)
    :ok
  end

  # -- Private --

  defp via(session_id) do
    {:via, Registry, {ZoomGate.Registry, {:analyzer, session_id}}}
  end

  defp emit_telemetry(session_id, changes) do
    Enum.each(changes, fn change ->
      {event_name, measurements, metadata} = telemetry_event(session_id, change)
      :telemetry.execute(event_name, measurements, metadata)
    end)
  end

  defp telemetry_event(session_id, {:status_changed, from, to}) do
    {[:zoom_gate, :analyzer, :status_changed], %{count: 1},
     %{session_id: session_id, from: from, to: to}}
  end

  defp telemetry_event(session_id, {:participant_added, data}) do
    {[:zoom_gate, :analyzer, :participant_added], %{count: 1},
     %{session_id: session_id, participant: data}}
  end

  defp telemetry_event(session_id, {:participant_removed, data}) do
    {[:zoom_gate, :analyzer, :participant_removed], %{count: 1},
     %{session_id: session_id, participant: data}}
  end

  defp telemetry_event(session_id, {:participant_updated, data}) do
    {[:zoom_gate, :analyzer, :participant_updated], %{count: 1},
     %{session_id: session_id, participant: data}}
  end

  defp telemetry_event(session_id, {:setting_changed, field, old_val, new_val}) do
    {[:zoom_gate, :analyzer, :setting_changed], %{count: 1},
     %{session_id: session_id, field: field, old_value: old_val, new_value: new_val}}
  end

  defp telemetry_event(session_id, {:chat_received, data}) do
    {[:zoom_gate, :analyzer, :chat_received], %{count: 1},
     %{session_id: session_id, message: data}}
  end

  defp telemetry_event(session_id, {:unknown_event, evt, body}) do
    {[:zoom_gate, :analyzer, :unknown_event], %{count: 1},
     %{session_id: session_id, evt: evt, body: body}}
  end

  defp telemetry_event(session_id, {type, data}) do
    {[:zoom_gate, :analyzer, type], %{count: 1}, %{session_id: session_id, data: data}}
  end

  defp notify_subscribers(subscribers, changes) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:analyzer, {:state_changes, changes}})
    end)
  end

  defp broadcast_pubsub(session_id, changes) do
    Phoenix.PubSub.broadcast(
      ZoomGate.PubSub,
      "analyzer:#{session_id}",
      {:analyzer, {:state_changes, changes}}
    )
  rescue
    _ -> :ok
  end
end
