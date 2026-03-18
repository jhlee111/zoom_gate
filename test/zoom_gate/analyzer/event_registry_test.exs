defmodule ZoomGate.Analyzer.EventRegistryTest do
  use ExUnit.Case, async: true

  alias ZoomGate.Analyzer.EventRegistry
  alias ZoomGate.Analyzer.EventRegistry.EventInfo

  describe "lookup/1" do
    test "returns EventInfo for known events" do
      assert {:ok, %EventInfo{code: 4098, name: "joinResponse"}} = EventRegistry.lookup(4098)
      assert {:ok, %EventInfo{code: 7937, name: "roster"}} = EventRegistry.lookup(7937)
    end

    test "returns :unknown for unregistered codes" do
      assert :unknown = EventRegistry.lookup(999_999)
    end
  end

  describe "known?/1" do
    test "returns true for catalogued events" do
      assert EventRegistry.known?(4098)
      assert EventRegistry.known?(7937)
      assert EventRegistry.known?(7938)
      assert EventRegistry.known?(4135)
      assert EventRegistry.known?(0)
    end

    test "returns false for unknown events" do
      refute EventRegistry.known?(999_999)
    end
  end

  describe "all currently handled events are in the registry" do
    test "server-to-client events used by MeetingBot" do
      # These are the events MeetingBot currently handles
      handled = [0, 4098, 7937, 7938, 7939, 7940, 7942, 7944, 7945]

      for evt <- handled do
        assert EventRegistry.known?(evt), "evt #{evt} should be in registry"
      end
    end

    test "client-to-server commands used by MeetingBot" do
      commands = [4097, 4101, 4103, 4107, 4109, 4111, 4113, 4135, 4199, 8193]

      for evt <- commands do
        assert EventRegistry.known?(evt), "evt #{evt} should be in registry"
      end
    end
  end

  describe "events_by_category/1" do
    test "waiting_room category includes relevant events" do
      events = EventRegistry.events_by_category(:waiting_room)
      codes = Enum.map(events, & &1.code)

      assert 4113 in codes
      assert 4117 in codes
      assert 4199 in codes
      assert 7942 in codes
    end

    test "chat category includes relevant events" do
      events = EventRegistry.events_by_category(:chat)
      codes = Enum.map(events, & &1.code)

      assert 4135 in codes
      assert 4136 in codes
      assert 4237 in codes
      assert 4238 in codes
      assert 7944 in codes
      assert 7960 in codes
    end

    test "breakout category includes relevant events" do
      events = EventRegistry.events_by_category(:breakout)
      codes = Enum.map(events, & &1.code)

      assert 4173 in codes
      assert 4175 in codes
      assert 4177 in codes
      assert 4179 in codes
    end
  end

  describe "direction/1" do
    test "correctly classifies client-to-server events" do
      assert :client_to_server = EventRegistry.direction(4097)
      assert :client_to_server = EventRegistry.direction(4107)
      assert :client_to_server = EventRegistry.direction(4135)
    end

    test "correctly classifies server-to-client events" do
      assert :server_to_client = EventRegistry.direction(4098)
      assert :server_to_client = EventRegistry.direction(7937)
      assert :server_to_client = EventRegistry.direction(7939)
    end

    test "returns :unknown for unregistered events" do
      assert :unknown = EventRegistry.direction(999_999)
    end
  end

  describe "categories/0" do
    test "returns all category atoms" do
      cats = EventRegistry.categories()

      assert :meeting in cats
      assert :participant in cats
      assert :chat in cats
      assert :waiting_room in cats
      assert :audio in cats
      assert :video in cats
      assert :sharing in cats
      assert :breakout in cats
      assert :caption in cats
      assert :recording in cats
    end
  end

  describe "no duplicate event codes" do
    test "all event codes are unique" do
      all = EventRegistry.all_events()
      codes = Enum.map(all, & &1.code)

      assert length(codes) == length(Enum.uniq(codes)),
             "Duplicate event codes found: #{inspect(codes -- Enum.uniq(codes))}"
    end
  end

  describe "coverage" do
    test "registry contains a substantial number of events" do
      all = EventRegistry.all_events()
      # We should have at least 100 events catalogued
      assert length(all) >= 100, "Only #{length(all)} events registered, expected >= 100"
    end
  end
end
