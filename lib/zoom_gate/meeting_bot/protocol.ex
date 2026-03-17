defmodule ZoomGate.MeetingBot.Protocol do
  @moduledoc """
  Zoom RWG WebSocket protocol constants, message encoding/decoding, and Base64 helpers.

  Event codes are exposed as macros so they can be used in pattern matching:

      require ZoomGate.MeetingBot.Protocol, as: Proto

      case msg do
        %{"evt" => Proto.evt_roster()} -> handle_roster(msg)
        %{"evt" => Proto.evt_end()}    -> handle_end(msg)
      end
  """

  # -- Server → Client events --

  defmacro evt_keepalive, do: 0
  defmacro evt_join_res, do: 4098
  defmacro evt_roster, do: 7937
  defmacro evt_attribute, do: 7938
  defmacro evt_end, do: 7939
  defmacro evt_host_change, do: 7940
  defmacro evt_hold_change, do: 7942
  defmacro evt_chat_indication, do: 7944
  defmacro evt_option, do: 7945

  # -- Client → Server commands --

  defmacro evt_join_req, do: 4097
  defmacro evt_end_req, do: 4101
  defmacro evt_leave_req, do: 4103
  defmacro evt_expel_req, do: 4107
  defmacro evt_rename_req, do: 4109
  defmacro evt_assign_host_req, do: 4111
  defmacro evt_put_on_hold_req, do: 4113
  defmacro evt_chat_req, do: 4135
  defmacro evt_admit_all_req, do: 4199
  defmacro evt_mute_req, do: 8193

  @doc "Encode a WebSocket message as JSON string."
  @spec encode(integer(), map() | nil, integer()) :: binary()
  def encode(evt, body, seq) do
    msg = %{"evt" => evt, "seq" => seq}
    msg = if body, do: Map.put(msg, "body", body), else: msg
    Jason.encode!(msg)
  end

  @doc "Decode a WebSocket JSON message."
  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(data) when is_binary(data), do: Jason.decode(data)

  @doc "URL-safe Base64 encode without padding."
  @spec b64_encode(binary()) :: binary()
  def b64_encode(str) when is_binary(str), do: Base.url_encode64(str, padding: false)

  @doc "URL-safe Base64 decode without padding. Returns original string on failure."
  @spec b64_decode(binary() | nil) :: binary()
  def b64_decode(nil), do: ""

  def b64_decode(str) when is_binary(str) do
    case Base.url_decode64(str, padding: false) do
      {:ok, decoded} -> decoded
      _ -> str
    end
  end
end
