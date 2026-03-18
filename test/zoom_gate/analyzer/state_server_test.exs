defmodule ZoomGate.Analyzer.StateServerTest do
  use ExUnit.Case, async: false

  alias ZoomGate.Analyzer.StateServer
  alias ZoomGate.Analyzer.EnrichedParticipant
  alias ZoomGate.Analyzer.MeetingSettings

  setup do
    session_id = "test-#{System.unique_integer([:positive])}"
    {:ok, pid} = StateServer.start_link(session_id: session_id, meeting_number: "123456789")
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{pid: pid, session_id: session_id}
  end

  describe "start_link/1" do
    test "initializes with empty state", %{pid: pid} do
      state = StateServer.get_state(pid)

      assert state.meeting_number == "123456789"
      assert state.status == :disconnected
      assert state.participants == %{}
      assert state.chat_history == []
    end
  end

  describe "inject_event/4" do
    test "with join response updates state", %{pid: pid} do
      event = %{"evt" => 4098, "body" => %{"res" => 0, "userID" => 100, "role" => 1}}
      raw = Jason.encode!(event)

      StateServer.inject_event(pid, :incoming, event, raw)

      state = StateServer.get_state(pid)
      assert state.status == :active
      assert state.self_user_id == 100
    end

    test "with roster add adds participants", %{pid: pid} do
      # First join
      join = %{"evt" => 4098, "body" => %{"res" => 0, "userID" => 1}}
      StateServer.inject_event(pid, :incoming, join, Jason.encode!(join))

      # Then roster add
      roster = %{
        "evt" => 7937,
        "body" => %{
          "add" => [
            %{
              "id" => 200,
              "dn2" => Base.url_encode64("Alice", padding: false),
              "bHold" => false,
              "userGUID" => "GUID-200"
            }
          ]
        }
      }

      StateServer.inject_event(pid, :incoming, roster, Jason.encode!(roster))

      participants = StateServer.get_participants(pid)
      assert map_size(participants) == 1
      assert %EnrichedParticipant{display_name: "Alice"} = participants[200]
    end

    test "records message in ETS", %{pid: pid} do
      event = %{"evt" => 7937, "body" => %{"add" => []}}
      raw = Jason.encode!(event)

      StateServer.inject_event(pid, :incoming, event, raw)

      records = StateServer.get_records(pid)
      assert length(records) == 1
      assert List.first(records).evt == 7937
    end
  end

  describe "get_state/1" do
    test "returns current ClientState snapshot", %{pid: pid} do
      state = StateServer.get_state(pid)
      assert state.meeting_number == "123456789"
      assert %MeetingSettings{} = state.meeting_settings
    end
  end

  describe "get_participants/1" do
    test "returns participant map", %{pid: pid} do
      assert StateServer.get_participants(pid) == %{}
    end
  end

  describe "get_records/1" do
    test "delegates to Recorder", %{pid: pid} do
      assert StateServer.get_records(pid) == []
    end
  end

  describe "get_unknowns/1" do
    test "returns unknown events", %{pid: pid} do
      event = %{"evt" => 99999, "body" => %{"mystery" => true}}
      StateServer.inject_event(pid, :incoming, event, Jason.encode!(event))

      unknowns = StateServer.get_unknowns(pid)
      assert length(unknowns) == 1
      assert List.first(unknowns).evt == 99999
    end
  end

  describe "get_correlations/1" do
    test "runs correlator on recorded data", %{pid: pid} do
      ts = System.monotonic_time(:microsecond)

      cmd = %{"evt" => 4135, "body" => %{"msgID" => "m1", "text" => "hi"}, "seq" => 1}
      resp = %{"evt" => 4136, "body" => %{"msgID" => "m1", "result" => 0}, "seq" => 2}

      StateServer.inject_event(pid, :outgoing, cmd, Jason.encode!(cmd))
      Process.sleep(1)
      StateServer.inject_event(pid, :incoming, resp, Jason.encode!(resp))

      correlations = StateServer.get_correlations(pid)
      assert length(correlations) >= 1
    end
  end

  describe "subscribe/1" do
    test "subscriber receives state changes", %{pid: pid} do
      StateServer.subscribe(pid)

      event = %{
        "evt" => 4098,
        "body" => %{"res" => 0, "userID" => 1, "role" => 1}
      }

      StateServer.inject_event(pid, :incoming, event, Jason.encode!(event))

      assert_receive {:analyzer, {:state_changes, changes}}, 1000
      assert is_list(changes)
      assert {:status_changed, :disconnected, :active} in changes
    end

    test "multiple subscribers receive changes", %{pid: pid} do
      # Subscribe from two processes
      StateServer.subscribe(pid)

      parent = self()

      task =
        Task.async(fn ->
          StateServer.subscribe(pid)
          send(parent, :task_subscribed)

          receive do
            {:analyzer, {:state_changes, _changes}} -> :received
          after
            1000 -> :timeout
          end
        end)

      # Wait for task to subscribe before injecting
      assert_receive :task_subscribed, 1000

      event = %{"evt" => 4098, "body" => %{"res" => 0, "userID" => 1}}
      StateServer.inject_event(pid, :incoming, event, Jason.encode!(event))

      assert_receive {:analyzer, {:state_changes, _}}, 1000
      assert Task.await(task) == :received
    end
  end

  describe "unknown event telemetry" do
    test "unknown events are recorded and discoverable", %{pid: pid} do
      for evt <- [55555, 66666, 77777] do
        event = %{"evt" => evt, "body" => %{"data" => evt}}
        StateServer.inject_event(pid, :incoming, event, Jason.encode!(event))
      end

      unknowns = StateServer.get_unknowns(pid)
      assert length(unknowns) == 3
      evts = Enum.map(unknowns, & &1.evt)
      assert 55555 in evts
      assert 66666 in evts
      assert 77777 in evts
    end
  end
end
