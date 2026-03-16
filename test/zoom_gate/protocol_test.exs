defmodule ZoomGate.ProtocolTest do
  use ExUnit.Case, async: true

  alias ZoomGate.Protocol

  describe "encode_command/1" do
    test "encodes a command map to newline-terminated JSON" do
      result = Protocol.encode_command(%{command: "admit", zoom_user_id: 123})
      assert String.ends_with?(result, "\n")
      assert {:ok, decoded} = Jason.decode(String.trim(result))
      assert decoded["command"] == "admit"
      assert decoded["zoom_user_id"] == 123
    end

    test "handles string keys" do
      result = Protocol.encode_command(%{"command" => "leave"})
      assert {:ok, %{"command" => "leave"}} = Jason.decode(String.trim(result))
    end
  end

  describe "decode_event/1" do
    test "decodes a valid JSON line" do
      assert {:ok, %{"event" => "joined"}} = Protocol.decode_event(~s({"event":"joined"}))
    end

    test "trims whitespace before decoding" do
      assert {:ok, %{"event" => "joined"}} = Protocol.decode_event(~s(  {"event":"joined"}  \n))
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = Protocol.decode_event("not json")
    end

    test "decodes event with payload" do
      json = ~s({"event":"waiting_room_join","zoom_user_id":42,"display_name":"Test"})
      assert {:ok, event} = Protocol.decode_event(json)
      assert event["event"] == "waiting_room_join"
      assert event["zoom_user_id"] == 42
      assert event["display_name"] == "Test"
    end
  end

  describe "valid_command?/1" do
    test "recognizes valid commands" do
      for cmd <- ~w(admit deny rename expel chat leave) do
        assert Protocol.valid_command?(cmd), "expected #{cmd} to be valid"
      end
    end

    test "rejects invalid commands" do
      refute Protocol.valid_command?("foo")
      refute Protocol.valid_command?("")
    end
  end

  describe "valid_event?/1" do
    test "recognizes valid events" do
      for evt <-
            ~w(joined waiting_room_join waiting_room_leave participant_joined participant_left meeting_ended error) do
        assert Protocol.valid_event?(evt), "expected #{evt} to be valid"
      end
    end

    test "rejects invalid events" do
      refute Protocol.valid_event?("foo")
    end
  end
end
