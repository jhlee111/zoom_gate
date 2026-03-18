defmodule ZoomGate.Analyzer.ChatMessageTest do
  use ExUnit.Case, async: true

  alias ZoomGate.Analyzer.ChatMessage

  describe "from_incoming/1" do
    test "parses evt 7944 body for a normal chat message" do
      body = %{
        "attendeeNodeID" => 0,
        "sn" => "zoom-id-sender",
        "destNodeID" => 0,
        "text" => "SGVsbG8gV29ybGQ",
        "senderName" => Base.url_encode64("Alice", padding: false),
        "msgID" => "msg-uuid-123"
      }

      msg = ChatMessage.from_incoming(body)

      assert msg.msg_id == "msg-uuid-123"
      assert msg.sender_id == "zoom-id-sender"
      assert msg.sender_name == "Alice"
      assert msg.dest_node_id == 0
      assert msg.raw_text == "SGVsbG8gV29ybGQ"
      assert msg.direction == :incoming
      assert msg.delivery_status == :delivered
      assert msg.deleted_at == nil
      assert %DateTime{} = msg.timestamp
    end

    test "parses waiting room chat (destNodeID = 4)" do
      body = %{
        "attendeeNodeID" => 4,
        "sn" => "host-zoom-id",
        "destNodeID" => 4,
        "text" => Base.url_encode64("Welcome to waiting room", padding: false),
        "senderName" => Base.url_encode64("Host", padding: false),
        "msgID" => "msg-wr-456"
      }

      msg = ChatMessage.from_incoming(body)

      assert msg.dest_node_id == 4
      assert msg.sender_name == "Host"
    end

    test "handles missing optional fields" do
      body = %{
        "destNodeID" => 0,
        "text" => "hello"
      }

      msg = ChatMessage.from_incoming(body)

      assert msg.msg_id == nil
      assert msg.sender_id == nil
      assert msg.sender_name == nil
      assert msg.dest_node_id == 0
      assert msg.direction == :incoming
    end
  end

  describe "from_outgoing/2" do
    test "creates a pending outgoing message" do
      body = %{
        "text" => "Hello everyone",
        "destNodeID" => 0,
        "msgID" => "out-msg-789"
      }

      msg = ChatMessage.from_outgoing(body)

      assert msg.msg_id == "out-msg-789"
      assert msg.dest_node_id == 0
      assert msg.raw_text == "Hello everyone"
      assert msg.direction == :outgoing
      assert msg.delivery_status == :pending
      assert %DateTime{} = msg.timestamp
    end

    test "creates outgoing waiting room message" do
      body = %{
        "text" => "Please wait",
        "destNodeID" => 4
      }

      msg = ChatMessage.from_outgoing(body)

      assert msg.dest_node_id == 4
      assert msg.direction == :outgoing
      assert msg.delivery_status == :pending
    end
  end

  describe "apply_confirmation/2" do
    test "updates delivery_status from evt 4136 success" do
      msg = %ChatMessage{
        msg_id: "msg-123",
        delivery_status: :pending,
        direction: :outgoing
      }

      confirmation = %{"result" => 0, "msgID" => "msg-123"}
      updated = ChatMessage.apply_confirmation(msg, confirmation)

      assert updated.delivery_status == :delivered
    end

    test "marks as blocked from evt 4136 block result" do
      msg = %ChatMessage{
        msg_id: "msg-123",
        delivery_status: :pending,
        direction: :outgoing
      }

      confirmation = %{"result" => 3, "msgID" => "msg-123"}
      updated = ChatMessage.apply_confirmation(msg, confirmation)

      assert updated.delivery_status == :blocked
    end
  end

  describe "apply_delete/2" do
    test "marks message as deleted from evt 7960" do
      msg = %ChatMessage{
        msg_id: "msg-123",
        delivery_status: :delivered,
        deleted_at: nil
      }

      delete_body = %{"cmd" => 1, "msgID" => "msg-123"}
      updated = ChatMessage.apply_delete(msg, delete_body)

      assert updated.delivery_status == :deleted
      assert %DateTime{} = updated.deleted_at
    end
  end
end
