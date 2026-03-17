defmodule ZoomGate.MeetingBot.Frame do
  @moduledoc """
  Binary frame encoding/decoding for Zoom RWG WebSocket protocol.

  The RWG WebSocket uses binary frames with a 17-byte header wrapping JSON payloads.

  ## Frame Types

  | Type | Direction | Purpose           |
  |------|-----------|-------------------|
  | 0x01 | send      | Client handshake  |
  | 0x02 | recv      | Server handshake  |
  | 0x03 | both      | Ping (16 bytes)   |
  | 0x04 | both      | Pong (16 bytes)   |
  | 0x05 | both      | Data frame        |

  ## Type 0x05 Header (17 bytes)

      [0]     type          = 0x05
      [1:3]   payload_len   = (total_len - 3), big-endian
      [3:5]   wire_seq      = auto-increment, big-endian
      [5]     zero          = 0x00
      [6:9]   magic         = "upo" (0x75 0x70 0x6f)
      [9:13]  timestamp     = monotonic counter, big-endian
      [13:15] last_recv_seq = ACK of last received server seq
      [15:17] reserved      = 0x0000
      [17:]   JSON payload
  """

  @type_handshake_server 0x02
  @type_ping 0x03
  @type_pong 0x04
  @type_data 0x05

  @magic "upo"

  @doc """
  Encode a JSON message into a binary data frame (type 0x05).

  ## Parameters
  - `json` - JSON string payload
  - `wire_seq` - frame sequence number (includes all frame types)
  - `timestamp` - monotonic timestamp counter
  - `last_recv_seq` - last received server sequence (for ACK)
  """
  @spec encode_data(binary(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: binary()
  def encode_data(json, wire_seq, timestamp, last_recv_seq) do
    payload_len = byte_size(json) + 14
    <<
      @type_data,
      payload_len::big-unsigned-16,
      wire_seq::big-unsigned-16,
      0x00,
      @magic::binary,
      timestamp::big-unsigned-32,
      last_recv_seq::big-unsigned-16,
      0::big-unsigned-16,
      json::binary
    >>
  end

  @doc """
  Encode a ping frame (type 0x03, 16 bytes).
  """
  @spec encode_ping(non_neg_integer(), non_neg_integer()) :: binary()
  def encode_ping(wire_seq, timestamp) do
    payload_len = 13
    <<
      @type_ping,
      payload_len::big-unsigned-16,
      wire_seq::big-unsigned-16,
      0x00, 0x01,
      timestamp::big-unsigned-32,
      @magic::binary,
      0x00
    >>
  end

  @doc """
  Encode a pong frame (type 0x04) echoing back a received ping.
  """
  @spec encode_pong(binary()) :: binary()
  def encode_pong(<<@type_ping, rest::binary>>) do
    <<@type_pong, rest::binary>>
  end

  @doc """
  Decode a binary WebSocket frame.

  Returns:
  - `{:data, json_string, server_seq}` for type 0x05 with JSON payload
  - `{:data_binary, payload, server_seq}` for type 0x05 without JSON
  - `{:handshake, payload}` for type 0x02
  - `{:ping, raw_frame}` for type 0x03
  - `{:pong, raw_frame}` for type 0x04
  - `{:unknown, type_byte}` for unrecognized types
  """
  @spec decode(binary()) :: {:data, binary(), non_neg_integer()}
    | {:data_binary, binary(), non_neg_integer()}
    | {:handshake, binary()}
    | {:ping, binary()}
    | {:pong, binary()}
    | {:unknown, byte()}
  def decode(<<@type_handshake_server, _rest::binary>> = frame) do
    {:handshake, frame}
  end

  def decode(<<@type_ping, _rest::binary>> = frame) do
    {:ping, frame}
  end

  def decode(<<@type_pong, _rest::binary>> = frame) do
    {:pong, frame}
  end

  def decode(<<@type_data, _payload_len::big-unsigned-16, wire_seq::big-unsigned-16, rest::binary>>)
      when byte_size(rest) >= 12 do
    <<_flags::binary-size(12), payload::binary>> = rest
    # Find JSON start
    case find_json_start(payload) do
      {:ok, json} ->
        {:data, json, wire_seq}
      :not_found ->
        {:data_binary, payload, wire_seq}
    end
  end

  def decode(<<type, _rest::binary>>) do
    {:unknown, type}
  end

  def decode(_), do: {:unknown, 0}

  # Find the first '{' in the payload — JSON starts there
  defp find_json_start(<<>>), do: :not_found
  defp find_json_start(<<"{", _::binary>> = data), do: {:ok, data}
  defp find_json_start(<<_byte, rest::binary>>), do: find_json_start(rest)
end
