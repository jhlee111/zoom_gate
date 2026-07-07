defmodule ZoomGate.Analyzer.CorrelatorTest do
  use ExUnit.Case, async: true

  alias ZoomGate.Analyzer.Correlator
  alias ZoomGate.Analyzer.Recorder.Record
  alias ZoomGate.Analyzer.EventRegistry

  defp make_record(evt, direction, opts \\ []) do
    {:ok, event_info} =
      if EventRegistry.known?(evt), do: EventRegistry.lookup(evt), else: {:ok, nil}

    %Record{
      id: Keyword.get(opts, :id, System.unique_integer([:positive])),
      session_id: "test",
      direction: direction,
      evt: evt,
      event_info: event_info,
      body: Keyword.get(opts, :body, %{}),
      seq: Keyword.get(opts, :seq, 0),
      raw_data: "",
      timestamp: Keyword.get(opts, :timestamp, System.monotonic_time(:microsecond)),
      wall_clock: DateTime.utc_now(),
      is_known: EventRegistry.known?(evt)
    }
  end

  describe "correlate/1" do
    test "matches admit command to roster updates" do
      ts = System.monotonic_time(:microsecond)

      records = [
        make_record(4113, :outgoing, body: %{"id" => 100, "bHold" => false}, timestamp: ts),
        make_record(7937, :incoming,
          body: %{"update" => [%{"id" => 100}]},
          timestamp: ts + 50_000
        ),
        make_record(7937, :incoming,
          body: %{"remove" => [%{"id" => 100}]},
          timestamp: ts + 100_000
        ),
        make_record(7937, :incoming, body: %{"add" => [%{"id" => 101}]}, timestamp: ts + 120_000)
      ]

      correlations = Correlator.correlate(records)
      assert length(correlations) >= 1

      corr = List.first(correlations)
      assert corr.command.evt == 4113
      assert length(corr.responses) >= 1
    end

    test "matches chat send to delivery confirmation by msgID" do
      ts = System.monotonic_time(:microsecond)

      records = [
        make_record(4135, :outgoing,
          body: %{"msgID" => "msg-123", "text" => "hi"},
          timestamp: ts
        ),
        make_record(4136, :incoming,
          body: %{"msgID" => "msg-123", "result" => 0},
          timestamp: ts + 30_000
        )
      ]

      correlations = Correlator.correlate(records)
      assert length(correlations) == 1

      corr = List.first(correlations)
      assert corr.command.evt == 4135
      assert List.first(corr.responses).evt == 4136
      assert corr.confidence == :known_pattern
    end

    test "matches expel to roster remove" do
      ts = System.monotonic_time(:microsecond)

      records = [
        make_record(4107, :outgoing, body: %{"id" => 200}, timestamp: ts),
        make_record(7937, :incoming,
          body: %{"remove" => [%{"id" => 200}]},
          timestamp: ts + 80_000
        )
      ]

      correlations = Correlator.correlate(records)
      assert length(correlations) == 1
      assert List.first(correlations).command.evt == 4107
    end

    test "matches join to join response" do
      ts = System.monotonic_time(:microsecond)

      records = [
        make_record(4097, :outgoing, body: %{"meetingtoken" => "tok"}, timestamp: ts),
        make_record(4098, :incoming, body: %{"res" => 0, "userID" => 1}, timestamp: ts + 200_000)
      ]

      correlations = Correlator.correlate(records)
      assert length(correlations) == 1
      assert List.first(correlations).command.evt == 4097
      assert List.first(correlations).responses |> List.first() |> Map.get(:evt) == 4098
    end

    test "computes latency between command and first response" do
      ts = System.monotonic_time(:microsecond)
      delay = 50_000

      records = [
        make_record(4101, :outgoing, timestamp: ts),
        make_record(7939, :incoming, body: %{"reason" => 8}, timestamp: ts + delay)
      ]

      correlations = Correlator.correlate(records)
      corr = List.first(correlations)

      assert corr.latency_us >= delay - 1000
      assert corr.latency_us <= delay + 1000
    end

    test "handles commands with no response" do
      records = [
        make_record(4113, :outgoing, body: %{"id" => 300, "bHold" => false})
      ]

      correlations = Correlator.correlate(records)
      assert correlations == [] || List.first(correlations).responses == []
    end

    test "handles responses with no matching command" do
      records = [
        make_record(7937, :incoming, body: %{"add" => [%{"id" => 1}]})
      ]

      correlations = Correlator.correlate(records)
      assert correlations == []
    end
  end

  describe "find_pattern/1" do
    test "returns known pattern for handled events" do
      assert %{} = Correlator.find_pattern(4113)
      assert %{} = Correlator.find_pattern(4135)
      assert %{} = Correlator.find_pattern(4107)
    end

    test "returns nil for unknown events" do
      assert Correlator.find_pattern(99999) == nil
    end
  end

  describe "discover_patterns/1" do
    test "suggests new patterns from timing proximity" do
      ts = System.monotonic_time(:microsecond)

      records = [
        # Unknown outgoing command
        make_record(4173, :outgoing, body: %{"topic" => "Room 1"}, timestamp: ts),
        # Unknown response shortly after
        make_record(4174, :incoming, body: %{"token" => "abc"}, timestamp: ts + 30_000),
        # Unrelated event much later
        make_record(7937, :incoming, body: %{"add" => []}, timestamp: ts + 5_000_000)
      ]

      suggestions = Correlator.discover_patterns(records)

      # Should suggest 4173 → 4174 as a pattern
      assert length(suggestions) >= 1
      suggestion = List.first(suggestions)
      assert suggestion.command_evt == 4173
      assert suggestion.response_evt == 4174
    end
  end
end
