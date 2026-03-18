defmodule ZoomGate.Analyzer.ChatMessage do
  @moduledoc """
  Chat message state with delivery tracking.

  Supports the full chat lifecycle: send → confirmation → delete.
  Tracks messages from evt 7944 (incoming), evt 4135 (outgoing),
  evt 4136 (delivery confirmation), and evt 7960 (server-initiated delete).
  """

  alias ZoomGate.MeetingBot.Protocol

  defstruct [
    :msg_id,
    :sender_id,
    :sender_name,
    :dest_node_id,
    :text,
    :raw_text,
    :direction,
    :timestamp,
    :delivery_status,
    :deleted_at
  ]

  @type direction :: :incoming | :outgoing

  @type delivery_status :: :pending | :delivered | :blocked | :deleted

  @type t :: %__MODULE__{
          msg_id: String.t() | nil,
          sender_id: String.t() | integer() | nil,
          sender_name: String.t() | nil,
          dest_node_id: integer() | nil,
          text: String.t() | nil,
          raw_text: String.t() | nil,
          direction: direction(),
          timestamp: DateTime.t(),
          delivery_status: delivery_status(),
          deleted_at: DateTime.t() | nil
        }

  @doc "Parse an incoming chat message from evt 7944 body."
  @spec from_incoming(map()) :: t()
  def from_incoming(body) when is_map(body) do
    %__MODULE__{
      msg_id: body["msgID"],
      sender_id: body["sn"],
      sender_name: decode_name(body["senderName"]),
      dest_node_id: body["destNodeID"],
      text: decode_text(body),
      raw_text: body["text"],
      direction: :incoming,
      timestamp: DateTime.utc_now(),
      delivery_status: :delivered,
      deleted_at: nil
    }
  end

  @doc "Create a pending outgoing message from evt 4135 body."
  @spec from_outgoing(map()) :: t()
  def from_outgoing(body) when is_map(body) do
    %__MODULE__{
      msg_id: body["msgID"],
      sender_id: nil,
      sender_name: nil,
      dest_node_id: body["destNodeID"],
      text: body["text"],
      raw_text: body["text"],
      direction: :outgoing,
      timestamp: DateTime.utc_now(),
      delivery_status: :pending,
      deleted_at: nil
    }
  end

  @doc "Update delivery status from evt 4136 confirmation."
  @spec apply_confirmation(t(), map()) :: t()
  def apply_confirmation(%__MODULE__{} = msg, %{"result" => result}) do
    status =
      case result do
        0 -> :delivered
        1 -> :deleted
        3 -> :blocked
        _ -> :delivered
      end

    %{msg | delivery_status: status}
  end

  @doc "Mark message as deleted from evt 7960."
  @spec apply_delete(t(), map()) :: t()
  def apply_delete(%__MODULE__{} = msg, _delete_body) do
    %{msg | delivery_status: :deleted, deleted_at: DateTime.utc_now()}
  end

  # -- Private --

  defp decode_name(nil), do: nil
  defp decode_name(name), do: Protocol.b64_decode(name)

  defp decode_text(%{"attendeeNodeID" => 4, "text" => text}) do
    # Waiting room messages are base64 only, not encrypted
    Protocol.b64_decode(text)
  end

  defp decode_text(%{"text" => text}), do: text
  defp decode_text(_), do: nil
end
