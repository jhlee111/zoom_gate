defmodule ZoomGate.GateChannelTest do
  use ExUnit.Case

  import Phoenix.ChannelTest

  @moduletag :capture_log

  @endpoint ZoomGate.Endpoint

  defp unique_id, do: "chan-test-#{System.unique_integer([:positive])}"

  defp create_session(meeting_id) do
    {:ok, _pid} = ZoomGate.SessionSupervisor.join_meeting(meeting_id, [])

    # Wait for session to become active by subscribing temporarily
    ZoomGate.Session.subscribe(meeting_id)
    assert_receive {:zoom_gate, {:bot_joined, _}}, 2000
    ZoomGate.Session.unsubscribe(meeting_id)
  end

  defp connect_and_join(meeting_id) do
    api_key = Application.get_env(:zoom_gate, :api_key)
    {:ok, socket} = connect(ZoomGate.Socket, %{"api_key" => api_key})
    subscribe_and_join(socket, ZoomGate.GateChannel, "gate:#{meeting_id}")
  end

  describe "join" do
    test "succeeds for active session" do
      mid = unique_id()
      create_session(mid)

      {:ok, _reply, _socket} = connect_and_join(mid)

      ZoomGate.SessionSupervisor.leave_meeting(mid)
    end

    test "fails for nonexistent session" do
      api_key = Application.get_env(:zoom_gate, :api_key)
      {:ok, socket} = connect(ZoomGate.Socket, %{"api_key" => api_key})

      assert {:error, %{reason: reason}} =
               subscribe_and_join(socket, ZoomGate.GateChannel, "gate:nonexistent")

      assert reason =~ "no active session"
    end
  end

  describe "commands" do
    setup do
      mid = unique_id()
      create_session(mid)
      {:ok, _reply, socket} = connect_and_join(mid)

      # Give subscriber registration time
      Process.sleep(50)

      on_exit(fn ->
        try do
          ZoomGate.SessionSupervisor.leave_meeting(mid)
        rescue
          _ -> :ok
        catch
          _, _ -> :ok
        end
      end)

      %{socket: socket, meeting_id: mid}
    end

    test "admit pushes participant_joined event", %{socket: socket} do
      ref = push(socket, "admit", %{"zoom_user_id" => 100, "display_name" => "Test"})
      assert_reply(ref, :ok)

      assert_push("participant_joined", %{zoom_user_id: 100, display_name: "Test"}, 2000)
    end

    test "deny pushes waiting_room_leave event", %{socket: socket} do
      ref = push(socket, "deny", %{"zoom_user_id" => 200})
      assert_reply(ref, :ok)

      assert_push("waiting_room_leave", %{zoom_user_id: 200}, 2000)
    end

    test "expel pushes participant_left event", %{socket: socket} do
      ref = push(socket, "expel", %{"zoom_user_id" => 300})
      assert_reply(ref, :ok)

      assert_push("participant_left", %{zoom_user_id: 300}, 2000)
    end

    test "rename succeeds", %{socket: socket} do
      ref = push(socket, "rename", %{"zoom_user_id" => 400, "display_name" => "New"})
      assert_reply(ref, :ok)
    end

    test "chat succeeds", %{socket: socket} do
      ref = push(socket, "chat", %{"message" => "Hello"})
      assert_reply(ref, :ok)
    end
  end

  describe "session death" do
    test "pushes meeting_ended when session terminates" do
      mid = unique_id()
      create_session(mid)
      {:ok, _reply, _socket} = connect_and_join(mid)
      Process.sleep(50)

      ZoomGate.SessionSupervisor.leave_meeting(mid)

      assert_push("meeting_ended", %{reason: "session_terminated"}, 2000)
    end
  end
end
