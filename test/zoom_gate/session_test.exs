defmodule ZoomGate.SessionTest do
  use ExUnit.Case

  alias ZoomGate.Session
  alias ZoomGate.SessionSupervisor

  @moduletag :capture_log

  # Helper to start a session and wait for :bot_joined
  defp start_session(meeting_id, extra_opts \\ []) do
    opts = Keyword.merge([callback: self()], extra_opts)
    {:ok, pid} = SessionSupervisor.join_meeting(meeting_id, opts)

    # Wait for the mock worker's automatic "joined" event
    assert_receive {:zoom_gate, {:bot_joined, %{meeting_id: ^meeting_id}}}, 2000
    pid
  end

  # Helper to generate unique meeting IDs per test
  defp unique_id, do: "test-#{System.unique_integer([:positive])}"

  describe "lifecycle" do
    test "starts and receives bot_joined event" do
      mid = unique_id()
      _pid = start_session(mid)
      status = Session.get_status(mid)
      assert status.status == :active
      assert status.meeting_id == mid
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
    test "admit sends command and receives participant_joined" do
      mid = unique_id()
      _pid = start_session(mid)

      Session.admit(mid, 42, display_name: "Alice")

      assert_receive {:zoom_gate,
                      {:participant_joined, %{zoom_user_id: 42, display_name: "Alice"}}},
                     2000
    end

    test "deny sends command and receives waiting_room_leave" do
      mid = unique_id()
      _pid = start_session(mid)

      Session.deny(mid, 42, message: "Not authorized")
      assert_receive {:zoom_gate, {:waiting_room_leave, %{zoom_user_id: 42}}}, 2000
    end

    test "expel sends command and receives participant_left" do
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
  end

  describe "events / simulate" do
    test "waiting_room_join updates state" do
      mid = unique_id()
      _pid = start_session(mid)

      # Use simulate command to inject a waiting_room_join event
      GenServer.call(Session.via(mid), {:send_chat, "", []})

      # Simulate via the port by sending a simulate command
      send_simulate(mid, %{
        "event" => "waiting_room_join",
        "zoom_user_id" => 99,
        "display_name" => "Bob",
        "email" => "bob@test.com"
      })

      assert_receive {:zoom_gate, {:waiting_room_join, %{zoom_user_id: 99, display_name: "Bob"}}},
                     2000

      status = Session.get_status(mid)
      assert Map.has_key?(status.waiting_room, 99)
    end

    test "participant tracking across admit/expel" do
      mid = unique_id()
      _pid = start_session(mid)

      Session.admit(mid, 10, display_name: "Charlie")
      assert_receive {:zoom_gate, {:participant_joined, %{zoom_user_id: 10}}}, 2000

      status = Session.get_status(mid)
      assert Map.has_key?(status.participants, 10)

      Session.expel(mid, 10)
      assert_receive {:zoom_gate, {:participant_left, %{zoom_user_id: 10}}}, 2000

      status = Session.get_status(mid)
      refute Map.has_key?(status.participants, 10)
    end
  end

  describe "subscribers" do
    test "subscriber receives events" do
      mid = unique_id()
      _pid = start_session(mid)

      # Start a subscriber process
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

      Session.admit(mid, 55, display_name: "Sub")
      assert_receive {:subscriber_got, {:participant_joined, %{zoom_user_id: 55}}}, 2000

      # Also received by callback (self)
      assert_receive {:zoom_gate, {:participant_joined, %{zoom_user_id: 55}}}, 2000

      # Clean up
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

      # Kill subscriber
      Process.exit(subscriber, :kill)
      Process.sleep(50)

      # Session should still be alive and functioning
      assert Process.alive?(pid)
      assert :ok = Session.admit(mid, 1)
    end
  end

  describe "port crash" do
    test "worker crash terminates session with exit event" do
      mid = unique_id()
      pid = start_session(mid)
      ref = Process.monitor(pid)

      :ok = send_raw_command(mid, %{command: "crash", exit_code: 42})

      assert_receive {:zoom_gate, {:meeting_ended, %{reason: :worker_exit, exit_code: 42}}}, 2000
      assert_receive {:DOWN, ^ref, :process, ^pid, {:worker_exited, 42}}, 2000
    end
  end

  # -- Helpers --

  defp send_simulate(meeting_id, event_data) do
    send_raw_command(meeting_id, %{command: "simulate", event_data: event_data})
  end

  defp send_raw_command(meeting_id, command) do
    # Access the port directly to send a command
    # We use GenServer internals — only for testing
    pid = Session.whereis(meeting_id)

    :sys.replace_state(pid, fn state ->
      json = Jason.encode!(command)
      Port.command(state.port, json <> "\n")
      state
    end)

    :ok
  end
end
