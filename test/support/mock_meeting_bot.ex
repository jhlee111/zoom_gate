defmodule ZoomGate.MockMeetingBot do
  @moduledoc """
  Mock MeetingBot for testing Session without Zoom connectivity.

  Simulates the MeetingBot GenServer by:
  - Sending {:meeting_bot_event, {:joined, ...}} on init
  - Responding to commands with simulated events (admit → participant_joined, etc.)
  - Supporting event injection via send_event/2
  """

  use GenServer

  # -- Public API (matches ZoomGate.MeetingBot) --

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

  def end_meeting(pid) do
    GenServer.call(pid, :end_meeting)
  end

  def leave(pid) do
    GenServer.call(pid, :leave)
  end

  @doc "Inject an event into the Session (test helper)."
  def send_event(pid, event) do
    GenServer.cast(pid, {:inject_event, event})
  end

  # -- GenServer --

  @impl true
  def init(opts) do
    session_pid = Keyword.fetch!(opts, :session_pid)
    meeting_number = Keyword.fetch!(opts, :meeting_number)

    # Simulate async connection + join
    Process.send_after(self(), :send_joined, 10)

    {:ok, %{session_pid: session_pid, meeting_number: meeting_number}}
  end

  @impl true
  def handle_info(:send_joined, state) do
    notify(
      state,
      {:joined,
       %{
         meeting_id: state.meeting_number,
         participant_id: 1,
         user_id: "mock-bot-user",
         role: 1
       }}
    )

    {:noreply, state}
  end

  # -- Commands --

  @impl true
  def handle_call({:put_on_hold, user_id, false}, _from, state) do
    # Admit: participant leaves WR, joins meeting
    notify(state, {:waiting_room_leave, %{zoom_user_id: user_id}})

    notify(
      state,
      {:participant_joined,
       %{
         zoom_user_id: user_id,
         display_name: "User #{user_id}"
       }}
    )

    {:reply, :ok, state}
  end

  def handle_call({:put_on_hold, user_id, true}, _from, state) do
    notify(state, {:participant_left, %{zoom_user_id: user_id}})
    notify(state, {:waiting_room_join, %{zoom_user_id: user_id, display_name: "User #{user_id}"}})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:expel, user_id}, _from, state) do
    notify(state, {:participant_left, %{zoom_user_id: user_id}})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:rename, _user_id, _old_name, _new_name}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:chat, _dest, _text}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:admit_all, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:mute, _user_id, _muted}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:end_meeting, _from, state) do
    notify(state, {:meeting_ended, %{reason: :host_ended}})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:leave, _from, state) do
    notify(state, {:meeting_ended, %{reason: :bot_left}})
    {:reply, :ok, state}
  end

  # Event injection
  @impl true
  def handle_cast({:inject_event, event}, state) do
    notify(state, event)
    {:noreply, state}
  end

  defp notify(state, event) do
    send(state.session_pid, {:meeting_bot_event, event})
  end
end
