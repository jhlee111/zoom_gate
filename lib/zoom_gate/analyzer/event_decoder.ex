defmodule ZoomGate.Analyzer.EventDecoder do
  @moduledoc """
  Decodes any RWG message with EventRegistry enrichment.

  Wraps `Protocol.decode` and `Frame.decode` to produce `DecodedEvent` structs
  that include registry metadata for known events and flag unknown events
  for protocol discovery.
  """

  alias ZoomGate.Analyzer.EventRegistry
  alias ZoomGate.MeetingBot.{Protocol, Frame}

  defmodule DecodedEvent do
    @moduledoc "A decoded and enriched RWG event."
    defstruct [:evt, :body, :seq, :event_info, :raw, :decoded_at, :is_known]

    @type t :: %__MODULE__{
            evt: integer() | nil,
            body: map() | nil,
            seq: integer() | nil,
            event_info: EventRegistry.EventInfo.t() | nil,
            raw: binary(),
            decoded_at: DateTime.t(),
            is_known: boolean()
          }
  end

  @doc "Decode a JSON string into a DecodedEvent with registry enrichment."
  @spec decode(binary()) :: {:ok, DecodedEvent.t()} | {:error, term()}
  def decode(json) when is_binary(json) do
    case Protocol.decode(json) do
      {:ok, parsed} ->
        evt = parsed["evt"]
        {event_info, is_known} = lookup_event(evt)

        decoded = %DecodedEvent{
          evt: evt,
          body: parsed["body"],
          seq: parsed["seq"],
          event_info: event_info,
          raw: json,
          decoded_at: DateTime.utc_now(),
          is_known: is_known
        }

        {:ok, decoded}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Decode a binary WebSocket frame into a DecodedEvent with frame metadata.

  Returns `{:ok, decoded_event, frame_metadata}` for data frames,
  or `{:ping, frame}` / `{:pong, frame}` / `{:handshake, frame}` for non-data frames.
  """
  @spec decode_frame(binary()) ::
          {:ok, DecodedEvent.t(), map()}
          | {:ping, binary()}
          | {:pong, binary()}
          | {:handshake, binary()}
          | {:error, term()}
  def decode_frame(frame) when is_binary(frame) do
    case Frame.decode(frame) do
      {:data, json, wire_seq} ->
        case decode(json) do
          {:ok, decoded} ->
            meta = %{wire_seq: wire_seq}
            {:ok, decoded, meta}

          {:error, reason} ->
            {:error, reason}
        end

      {:data_binary, _payload, _wire_seq} ->
        {:error, :non_json_payload}

      {:ping, raw} ->
        {:ping, raw}

      {:pong, raw} ->
        {:pong, raw}

      {:handshake, raw} ->
        {:handshake, raw}

      {:unknown, _type} ->
        {:error, :unknown_frame_type}
    end
  end

  defp lookup_event(nil), do: {nil, false}

  defp lookup_event(evt) do
    case EventRegistry.lookup(evt) do
      {:ok, info} -> {info, true}
      :unknown -> {nil, false}
    end
  end
end
