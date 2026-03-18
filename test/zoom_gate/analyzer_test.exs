defmodule ZoomGate.AnalyzerTest do
  use ExUnit.Case, async: false

  alias ZoomGate.Analyzer

  describe "enable/2 and disable/1" do
    test "starts and stops analyzer components" do
      session_id = "facade-#{System.unique_integer([:positive])}"

      assert {:ok, %{state_server: ss, tap: tap}} =
               Analyzer.enable(session_id, meeting_number: "12345")

      assert Process.alive?(ss)
      assert Process.alive?(tap)

      assert :ok = Analyzer.disable(session_id)
      Process.sleep(50)
      refute Process.alive?(ss)
      refute Process.alive?(tap)
    end

    test "enable is idempotent" do
      session_id = "facade-idem-#{System.unique_integer([:positive])}"

      {:ok, pids1} = Analyzer.enable(session_id, meeting_number: "12345")
      {:ok, pids2} = Analyzer.enable(session_id, meeting_number: "12345")

      # Should return the same pids (already running)
      assert pids1.state_server == pids2.state_server

      Analyzer.disable(session_id)
    end
  end

  describe "get_state/1" do
    test "returns enriched client state" do
      session_id = "facade-state-#{System.unique_integer([:positive])}"
      {:ok, %{tap: tap}} = Analyzer.enable(session_id, meeting_number: "999")

      # Inject an event through the tap
      json = Jason.encode!(%{"evt" => 4098, "body" => %{"res" => 0, "userID" => 1}})
      send(tap, {:raw_ws, :incoming, json})
      Process.sleep(50)

      state = Analyzer.get_state(session_id)
      assert state.status == :active

      Analyzer.disable(session_id)
    end
  end

  describe "export/1" do
    test "returns complete session data" do
      session_id = "facade-export-#{System.unique_integer([:positive])}"
      {:ok, %{tap: tap}} = Analyzer.enable(session_id, meeting_number: "999")

      json = Jason.encode!(%{"evt" => 7937, "body" => %{"add" => []}})
      send(tap, {:raw_ws, :incoming, json})
      Process.sleep(50)

      exported = Analyzer.export(session_id)
      assert is_list(exported)
      assert length(exported) == 1

      Analyzer.disable(session_id)
    end
  end
end
