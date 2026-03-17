defmodule ZoomGate.SessionTest do
  use ExUnit.Case

  alias ZoomGate.Session
  alias ZoomGate.SessionSupervisor

  @moduletag :capture_log

  # Helper to start a session and wait for :bot_joined
  defp start_session(meeting_id, extra_opts \\ []) do
    opts = Keyword.merge([callback: self()], extra_opts)
    {:ok, pid} = SessionSupervisor.join_meeting(meeting_id, opts)

    # Wait for the mock MeetingBot's "joined" event
    assert_receive {:zoom_gate, {:bot_joined, %{meeting_id: ^meeting_id}}}, 2000
    pid
  end

  # Helper to generate unique meeting IDs per test
  defp unique_id, do: "test-#{System.unique_integer([:positive])}"

  # Helper to inject events into a Session via its MeetingBot
  defp inject_event(meeting_id, event) do
    pid = Session.whereis(meeting_id)
    send(pid, {:meeting_bot_event, event})
  end

  describe "lifecycle" do
    test "starts and receives bot_joined event" do
      mid = unique_id()
      _pid = start_session(mid)
      status = Session.get_status(mid)
      assert status.status == :active
      assert status.meeting_id == mid
    end

    test "max_sessions limit rejects new sessions" do
      original = Application.get_env(:zoom_gate, :max_sessions)
      # Use current count + 1 as limit to avoid interfering with parallel tests
      current = SessionSupervisor.count_sessions()
      Application.put_env(:zoom_gate, :max_sessions, current + 1)

      on_exit(fn ->
        if original,
          do: Application.put_env(:zoom_gate, :max_sessions, original),
          else: Application.delete_env(:zoom_gate, :max_sessions)
      end)

      mid1 = unique_id()
      _pid = start_session(mid1)

      mid2 = unique_id()
      assert {:error, :max_sessions_reached} = SessionSupervisor.join_meeting(mid2, [])

      SessionSupervisor.leave_meeting(mid1)
      Process.sleep(50)
    end

    test "registers in Registry" do
      mid = unique_id()
      pid = start_session(mid)
      assert Session.whereis(mid) == pid
    end

    test "leave_meeting terminates the session" do
      mid = unique_id()
      pid = start_session(mid)
      ref = Process.monitor(pid)

      SessionSupervisor.leave_meeting(mid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2000
      Process.sleep(50)
      assert Session.whereis(mid) == nil
    end
  end

  describe "commands" do
    test "admit sends put_on_hold(false) and receives events" do
      mid = unique_id()
      _pid = start_session(mid)

      Session.admit(mid, 42)

      # MockMeetingBot sends waiting_room_leave + participant_joined
      assert_receive {:zoom_gate, {:waiting_room_leave, %{zoom_user_id: 42}}}, 2000
      assert_receive {:zoom_gate, {:participant_joined, %{zoom_user_id: 42}}}, 2000
    end

    test "deny sends expel and receives participant_left" do
      mid = unique_id()
      _pid = start_session(mid)

      Session.deny(mid, 42)
      assert_receive {:zoom_gate, {:participant_left, %{zoom_user_id: 42}}}, 2000
    end

    test "expel sends expel and receives participant_left" do
      mid = unique_id()
      _pid = start_session(mid)

      Session.expel(mid, 42)
      assert_receive {:zoom_gate, {:participant_left, %{zoom_user_id: 42}}}, 2000
    end

    test "rename sends command (no event expected)" do
      mid = unique_id()
      _pid = start_session(mid)

      assert :ok = Session.rename(mid, 42, "New Name")
    end

    test "send_chat sends command (no event expected)" do
      mid = unique_id()
      _pid = start_session(mid)

      assert :ok = Session.send_chat(mid, "Hello!", to: 42)
    end

    test "chat_waiting_room sends command (no event expected)" do
      mid = unique_id()
      _pid = start_session(mid)

      assert :ok = Session.chat_waiting_room(mid, "안녕하세요, 성함을 확인해주세요")
    end

    test "admit_all sends command (no event expected)" do
      mid = unique_id()
      _pid = start_session(mid)

      assert :ok = Session.admit_all(mid)
    end

    test "mute sends command (no event expected)" do
      mid = unique_id()
      _pid = start_session(mid)

      assert :ok = Session.mute(mid, 42)
    end

    test "end_meeting sends command and receives meeting_ended" do
      mid = unique_id()
      pid = start_session(mid)
      ref = Process.monitor(pid)

      Session.end_meeting(mid)
      assert_receive {:zoom_gate, {:meeting_ended, %{reason: :host_ended}}}, 2000
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000
    end
  end

  describe "event injection" do
    test "waiting_room_join updates state" do
      mid = unique_id()
      _pid = start_session(mid)

      inject_event(mid, {:waiting_room_join, %{zoom_user_id: 99, display_name: "Bob"}})

      assert_receive {:zoom_gate, {:waiting_room_join, %{zoom_user_id: 99, display_name: "Bob"}}},
                     2000

      status = Session.get_status(mid)
      assert Map.has_key?(status.waiting_room, 99)
    end

    test "participant tracking across admit/expel" do
      mid = unique_id()
      _pid = start_session(mid)

      # Inject participant_joined
      inject_event(mid, {:participant_joined, %{zoom_user_id: 10, display_name: "Charlie"}})
      assert_receive {:zoom_gate, {:participant_joined, %{zoom_user_id: 10}}}, 2000

      status = Session.get_status(mid)
      assert Map.has_key?(status.participants, 10)

      # Inject participant_left
      inject_event(mid, {:participant_left, %{zoom_user_id: 10}})
      assert_receive {:zoom_gate, {:participant_left, %{zoom_user_id: 10}}}, 2000

      status = Session.get_status(mid)
      refute Map.has_key?(status.participants, 10)
    end

    test "chat_received delivers event" do
      mid = unique_id()
      _pid = start_session(mid)

      inject_event(mid, {:chat_received, %{from_user_id: 5, message: "Hello"}})
      assert_receive {:zoom_gate, {:chat_received, %{from_user_id: 5, message: "Hello"}}}, 2000
    end

    test "host_changed delivers event" do
      mid = unique_id()
      _pid = start_session(mid)

      inject_event(mid, {:host_changed, %{new_host_id: 7}})
      assert_receive {:zoom_gate, {:host_changed, %{new_host_id: 7}}}, 2000
    end
  end

  describe "subscribers" do
    test "subscriber receives events" do
      mid = unique_id()
      _pid = start_session(mid)

      test_pid = self()

      subscriber =
        spawn(fn ->
          Session.subscribe(mid)

          receive do
            {:zoom_gate, event} -> send(test_pid, {:subscriber_got, event})
          end
        end)

      # Give subscriber time to register
      Process.sleep(50)

      Session.admit(mid, 55)
      assert_receive {:subscriber_got, {:waiting_room_leave, %{zoom_user_id: 55}}}, 2000

      Process.exit(subscriber, :kill)
    end

    test "subscriber cleanup on process death" do
      mid = unique_id()
      pid = start_session(mid)

      subscriber =
        spawn(fn ->
          Session.subscribe(mid)
          Process.sleep(:infinity)
        end)

      Process.sleep(50)

      Process.exit(subscriber, :kill)
      Process.sleep(50)

      # Session should still be alive and functioning
      assert Process.alive?(pid)
      assert :ok = Session.admit(mid, 1)
    end
  end

  describe "meeting_bot crash" do
    test "MeetingBot crash terminates session with exit event" do
      mid = unique_id()
      pid = start_session(mid)
      ref = Process.monitor(pid)

      # Get the MeetingBot PID and kill it
      %{meeting_bot: wc_pid} = :sys.get_state(pid)
      Process.exit(wc_pid, :kill)

      assert_receive {:zoom_gate, {:meeting_ended, %{reason: :worker_exit}}}, 2000
      assert_receive {:DOWN, ^ref, :process, ^pid, {:meeting_bot_exited, :killed}}, 2000
    end
  end
end
