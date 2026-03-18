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

  def start_recording(pid), do: GenServer.call(pid, :start_recording)

  def stop_recording(pid), do: GenServer.call(pid, :stop_recording)

  def lock_sharing(pid, locked), do: GenServer.call(pid, {:lock_sharing, locked})

  def spotlight(pid, user_id, spotlight),
    do: GenServer.call(pid, {:spotlight, user_id, spotlight})

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

    {:ok, %{session_pid: session_pid, meeting_number: meeting_number, participants: %{}}}
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

    p = %{
      zoom_user_id: user_id,
      display_name: "User #{user_id}",
      role: 0,
      is_host: false,
      is_cohost: false,
      muted: false,
      video_on: false
    }

    notify(state, {:participant_joined, p})

    participants =
      state.participants
      |> Map.delete(user_id)
      |> Map.put(user_id, p)

    {:reply, :ok, %{state | participants: participants}}
  end

  def handle_call({:put_on_hold, user_id, true}, _from, state) do
    notify(state, {:participant_left, %{zoom_user_id: user_id}})

    p = %{
      zoom_user_id: user_id,
      display_name: "User #{user_id}",
      role: 0,
      is_host: false,
      is_cohost: false,
      muted: false,
      video_on: false,
      b_hold: true
    }

    notify(state, {:waiting_room_join, %{zoom_user_id: user_id, display_name: "User #{user_id}"}})
    participants = Map.put(state.participants, user_id, p)
    {:reply, :ok, %{state | participants: participants}}
  end

  @impl true
  def handle_call({:expel, user_id}, _from, state) do
    notify(state, {:participant_left, %{zoom_user_id: user_id}})
    {:reply, :ok, %{state | participants: Map.delete(state.participants, user_id)}}
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
  def handle_call(:start_recording, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stop_recording, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:lock_sharing, _locked}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:spotlight, _user_id, _spotlight}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_participants, _from, state) do
    {:reply, state.participants, state}
  end

  @impl true
  def handle_call(:get_health, _from, state) do
    {:reply, %{status: :active, heartbeat_age_ms: 0, reconnect_attempts: 0, participant_count: 0},
     state}
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
    state = track_injected_event(state, event)
    {:noreply, state}
  end

  defp track_injected_event(state, {:participant_joined, %{zoom_user_id: uid} = p}) do
    %{state | participants: Map.put(state.participants, uid, p)}
  end

  defp track_injected_event(state, {:waiting_room_join, %{zoom_user_id: uid} = p}) do
    %{state | participants: Map.put(state.participants, uid, Map.put(p, :b_hold, true))}
  end

  defp track_injected_event(state, {:participant_left, %{zoom_user_id: uid}}) do
    %{state | participants: Map.delete(state.participants, uid)}
  end

  defp track_injected_event(state, {:waiting_room_leave, %{zoom_user_id: uid}}) do
    %{state | participants: Map.delete(state.participants, uid)}
  end

  defp track_injected_event(state, _), do: state

  defp notify(state, event) do
    send(state.session_pid, {:meeting_bot_event, event})
  end
end
