defmodule ZoomGate.MeetingBot.ProtocolTest do
  use ExUnit.Case, async: true

  require ZoomGate.MeetingBot.Protocol, as: Proto

  describe "evt macros" do
    test "server event codes" do
      assert Proto.evt_keepalive() == 0
      assert Proto.evt_join_res() == 4098
      assert Proto.evt_roster() == 7937
      assert Proto.evt_attribute() == 7938
      assert Proto.evt_end() == 7939
      assert Proto.evt_host_change() == 7940
      assert Proto.evt_hold_change() == 7942
      assert Proto.evt_chat_indication() == 7944
      assert Proto.evt_option() == 7945
    end

    test "client command codes" do
      assert Proto.evt_join_req() == 4097
      assert Proto.evt_end_req() == 4101
      assert Proto.evt_leave_req() == 4103
      assert Proto.evt_expel_req() == 4107
      assert Proto.evt_rename_req() == 4109
      assert Proto.evt_put_on_hold_req() == 4113
      assert Proto.evt_chat_req() == 4135
      assert Proto.evt_admit_all_req() == 4199
      assert Proto.evt_mute_req() == 8193
    end

    test "macros work in pattern matching" do
      msg = %{"evt" => 7937, "body" => %{"add" => []}}

      result =
        case msg do
          %{"evt" => Proto.evt_roster()} -> :roster
          %{"evt" => Proto.evt_end()} -> :end
          _ -> :other
        end

      assert result == :roster
    end
  end

  describe "encode/3" do
    test "encodes message with body" do
      json = Proto.encode(4107, %{id: 42}, 1)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["evt"] == 4107
      assert decoded["body"]["id"] == 42
      assert decoded["seq"] == 1
    end

    test "encodes message without body" do
      json = Proto.encode(0, nil, 5)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["evt"] == 0
      assert decoded["seq"] == 5
      refute Map.has_key?(decoded, "body")
    end
  end

  describe "decode/1" do
    test "decodes valid JSON" do
      assert {:ok, %{"evt" => 7937}} = Proto.decode(~s({"evt":7937}))
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = Proto.decode("not json")
    end
  end

  describe "b64_encode/1" do
    test "encodes string without padding" do
      assert Proto.b64_encode("Hello") == Base.url_encode64("Hello", padding: false)
    end
  end

  describe "b64_decode/1" do
    test "decodes valid base64" do
      encoded = Base.url_encode64("안녕", padding: false)
      assert Proto.b64_decode(encoded) == "안녕"
    end

    test "returns empty string for nil" do
      assert Proto.b64_decode(nil) == ""
    end

    test "returns original string on decode failure" do
      assert Proto.b64_decode("not-valid-b64!!!") == "not-valid-b64!!!"
    end
  end
end
