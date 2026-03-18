defmodule ZoomGate.Analyzer.EventDecoderTest do
  use ExUnit.Case, async: true

  alias ZoomGate.Analyzer.EventDecoder
  alias ZoomGate.Analyzer.EventDecoder.DecodedEvent
  alias ZoomGate.Analyzer.EventRegistry.EventInfo
  alias ZoomGate.MeetingBot.Frame

  describe "decode/1" do
    test "enriches known event with EventInfo" do
      json = Jason.encode!(%{"evt" => 7937, "body" => %{"add" => []}, "seq" => 1})
      assert {:ok, %DecodedEvent{} = decoded} = EventDecoder.decode(json)

      assert decoded.evt == 7937
      assert decoded.body == %{"add" => []}
      assert decoded.seq == 1
      assert decoded.is_known == true
      assert %EventInfo{code: 7937, name: "roster"} = decoded.event_info
      assert decoded.raw == json
    end

    test "marks unknown event with is_known: false" do
      json = Jason.encode!(%{"evt" => 999_999, "body" => %{"x" => 1}, "seq" => 5})
      assert {:ok, %DecodedEvent{} = decoded} = EventDecoder.decode(json)

      assert decoded.evt == 999_999
      assert decoded.is_known == false
      assert decoded.event_info == nil
    end

    test "preserves raw data" do
      json = Jason.encode!(%{"evt" => 4098, "body" => %{"res" => 0}, "seq" => 0})
      assert {:ok, decoded} = EventDecoder.decode(json)
      assert decoded.raw == json
    end

    test "handles malformed JSON gracefully" do
      assert {:error, _reason} = EventDecoder.decode("not json {{{")
    end

    test "handles missing evt field" do
      json = Jason.encode!(%{"body" => %{"something" => true}})
      assert {:ok, decoded} = EventDecoder.decode(json)
      assert decoded.evt == nil
      assert decoded.is_known == false
    end
  end

  describe "decode_frame/1" do
    test "handles type 0x05 binary data frames" do
      json = Jason.encode!(%{"evt" => 7944, "body" => %{"text" => "hello"}, "seq" => 3})
      wire_seq = 42
      timestamp = 1000
      last_recv_seq = 10

      frame = Frame.encode_data(json, wire_seq, timestamp, last_recv_seq)

      assert {:ok, decoded, frame_meta} = EventDecoder.decode_frame(frame)

      assert decoded.evt == 7944
      assert decoded.body == %{"text" => "hello"}
      assert decoded.is_known == true
      assert frame_meta.wire_seq == wire_seq
    end

    test "handles non-JSON binary payloads" do
      # Type 0x03 ping frame
      json = Jason.encode!(%{"evt" => 0, "body" => %{}, "seq" => 0})
      frame = Frame.encode_data(json, 1, 0, 0)
      ping = Frame.encode_ping(2, 100)

      assert {:ok, _decoded, _meta} = EventDecoder.decode_frame(frame)
      assert {:ping, _} = EventDecoder.decode_frame(ping)
    end
  end
end
