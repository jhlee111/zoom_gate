defmodule ZoomGate.Analyzer.RecorderTest do
  use ExUnit.Case, async: false

  alias ZoomGate.Analyzer.Recorder
  alias ZoomGate.Analyzer.EventDecoder

  setup do
    session_id = "test-#{System.unique_integer([:positive])}"
    Recorder.new(session_id)
    on_exit(fn -> Recorder.destroy(session_id) end)
    %{session_id: session_id}
  end

  describe "new/1 and destroy/1" do
    test "creates and destroys ETS table", %{session_id: session_id} do
      assert Recorder.count(session_id) == 0
      assert :ok = Recorder.destroy(session_id)
    end
  end

  describe "record/4" do
    test "appends records to the log", %{session_id: session_id} do
      json = Jason.encode!(%{"evt" => 7937, "body" => %{"add" => []}, "seq" => 1})
      {:ok, decoded} = EventDecoder.decode(json)

      Recorder.record(session_id, :incoming, decoded, json)
      assert Recorder.count(session_id) == 1

      Recorder.record(session_id, :outgoing, decoded, json)
      assert Recorder.count(session_id) == 2
    end
  end

  describe "get_all/1" do
    test "returns records in insertion order", %{session_id: session_id} do
      for i <- 1..5 do
        json = Jason.encode!(%{"evt" => 7937, "body" => %{}, "seq" => i})
        {:ok, decoded} = EventDecoder.decode(json)
        Recorder.record(session_id, :incoming, decoded, json)
      end

      records = Recorder.get_all(session_id)
      assert length(records) == 5

      seqs = Enum.map(records, & &1.seq)
      assert seqs == [1, 2, 3, 4, 5]
    end
  end

  describe "get_by_evt/2" do
    test "filters records by event code", %{session_id: session_id} do
      record_event(session_id, 7937, :incoming)
      record_event(session_id, 7944, :incoming)
      record_event(session_id, 7937, :incoming)
      record_event(session_id, 4098, :incoming)

      roster_records = Recorder.get_by_evt(session_id, 7937)
      assert length(roster_records) == 2

      chat_records = Recorder.get_by_evt(session_id, 7944)
      assert length(chat_records) == 1
    end
  end

  describe "get_by_category/2" do
    test "filters by event category", %{session_id: session_id} do
      record_event(session_id, 7937, :incoming)
      record_event(session_id, 7944, :incoming)
      record_event(session_id, 4135, :outgoing)
      record_event(session_id, 4098, :incoming)

      chat_records = Recorder.get_by_category(session_id, :chat)
      assert length(chat_records) == 2
    end
  end

  describe "get_unknowns/1" do
    test "returns only unknown events", %{session_id: session_id} do
      record_event(session_id, 7937, :incoming)
      record_event(session_id, 99999, :incoming)
      record_event(session_id, 88888, :incoming)

      unknowns = Recorder.get_unknowns(session_id)
      assert length(unknowns) == 2
      assert Enum.all?(unknowns, &(&1.is_known == false))
    end
  end

  describe "get_range/3" do
    test "filters by timestamp range", %{session_id: session_id} do
      record_event(session_id, 7937, :incoming)
      ts_after_first = System.monotonic_time(:microsecond)
      record_event(session_id, 7944, :incoming)
      record_event(session_id, 4098, :incoming)

      # Records after ts_after_first
      records = Recorder.get_range(session_id, ts_after_first, nil)
      assert length(records) == 2
    end
  end

  describe "export/1" do
    test "returns serializable data", %{session_id: session_id} do
      record_event(session_id, 7937, :incoming)
      record_event(session_id, 4135, :outgoing)

      exported = Recorder.export(session_id)
      assert length(exported) == 2
      assert is_map(List.first(exported))
    end
  end

  describe "concurrent access" do
    test "concurrent reads don't block writes", %{session_id: session_id} do
      # Write 100 records in parallel
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            record_event(session_id, 7937, :incoming, i)
          end)
        end

      Task.await_many(tasks)

      assert Recorder.count(session_id) == 100
    end
  end

  # Helper
  defp record_event(session_id, evt, direction, seq \\ 0) do
    json = Jason.encode!(%{"evt" => evt, "body" => %{}, "seq" => seq})
    {:ok, decoded} = EventDecoder.decode(json)
    Recorder.record(session_id, direction, decoded, json)
  end
end
