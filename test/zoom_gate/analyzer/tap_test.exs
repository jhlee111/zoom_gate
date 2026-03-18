defmodule ZoomGate.Analyzer.TapTest do
  use ExUnit.Case, async: false

  alias ZoomGate.Analyzer.{Tap, StateServer}

  setup do
    session_id = "tap-test-#{System.unique_integer([:positive])}"

    {:ok, state_server} =
      StateServer.start_link(session_id: session_id, meeting_number: "999")

    %{session_id: session_id, state_server: state_server}
  end

  describe "start_link/1" do
    test "starts the tap process", %{session_id: session_id, state_server: state_server} do
      {:ok, pid} = Tap.start_link(session_id: session_id, state_server: state_server)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "message forwarding" do
    test "forwards incoming text messages to StateServer", %{
      session_id: session_id,
      state_server: state_server
    } do
      {:ok, tap} = Tap.start_link(session_id: session_id, state_server: state_server)

      # Simulate MeetingBot sending raw WS data to the tap
      json = Jason.encode!(%{"evt" => 4098, "body" => %{"res" => 0, "userID" => 42, "role" => 1}})
      send(tap, {:raw_ws, :incoming, json})

      # Give it time to process
      Process.sleep(50)

      state = StateServer.get_state(state_server)
      assert state.status == :active
      assert state.self_user_id == 42

      GenServer.stop(tap)
    end

    test "forwards outgoing messages to StateServer", %{
      session_id: session_id,
      state_server: state_server
    } do
      {:ok, tap} = Tap.start_link(session_id: session_id, state_server: state_server)

      json =
        Jason.encode!(%{
          "evt" => 4135,
          "body" => %{"text" => "hello", "destNodeID" => 0},
          "seq" => 1
        })

      send(tap, {:raw_ws, :outgoing, json})

      Process.sleep(50)

      records = StateServer.get_records(state_server)
      assert length(records) == 1
      assert List.first(records).direction == :outgoing

      GenServer.stop(tap)
    end

    test "handles binary frames (as_type=2)", %{
      session_id: session_id,
      state_server: state_server
    } do
      {:ok, tap} = Tap.start_link(session_id: session_id, state_server: state_server)

      json = Jason.encode!(%{"evt" => 7937, "body" => %{"add" => []}, "seq" => 1})
      frame = ZoomGate.MeetingBot.Frame.encode_data(json, 1, 100, 0)
      send(tap, {:raw_ws, :incoming, {:binary, frame}})

      Process.sleep(50)

      records = StateServer.get_records(state_server)
      assert length(records) == 1

      GenServer.stop(tap)
    end
  end
end
