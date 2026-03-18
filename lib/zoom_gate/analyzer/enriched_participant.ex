defmodule ZoomGate.Analyzer.EnrichedParticipant do
  @moduledoc """
  Extended participant state with all known RWG protocol fields.

  This struct captures every field available from evt 7937 roster updates,
  including fields not tracked by the existing `ZoomGate.MeetingBot.Participant`.
  Unknown fields are automatically captured in `raw_extra` for protocol discovery.
  """

  alias ZoomGate.MeetingBot.Protocol

  defstruct [
    # nil-default fields first
    :id,
    :display_name,
    :zoom_id,
    :avatar,
    :user_guid,
    :str_conf_user_id,
    :email,
    :pronouns,
    :customer_key,
    :user_type,
    :os,
    :pwa_os,
    :caps,
    :unique_index,
    :audio_connection_status,
    :action,
    :n_user_status,
    :b_in_failover,
    :bid,

    # keyword-default fields
    role: 0,
    is_host: false,
    is_cohost: false,
    muted: false,
    video_on: false,
    b_hold: false,
    b_share_on: false,
    b_share_pause: false,
    b_video_connect: false,
    b_guest: false,
    b_local_record: false,
    hand_raised: false,
    raw_extra: %{}
  ]

  @type t :: %__MODULE__{}

  # Map of raw JSON field names to struct field names
  @field_map %{
    "id" => :id,
    "dn2" => :display_name,
    "zoomID" => :zoom_id,
    "avatar" => :avatar,
    "role" => :role,
    "isHost" => :is_host,
    "isCoHost" => :is_cohost,
    "muted" => :muted,
    "bVideoOn" => :video_on,
    "bHold" => :b_hold,
    "userGUID" => :user_guid,
    "strConfUserID" => :str_conf_user_id,
    "email" => :email,
    "strPronoun" => :pronouns,
    "customerKey" => :customer_key,
    "type" => :user_type,
    "os" => :os,
    "pwaOS" => :pwa_os,
    "caps" => :caps,
    "uniqueIndex" => :unique_index,
    "bShareOn" => :b_share_on,
    "bSharePause" => :b_share_pause,
    "bVideoConnect" => :b_video_connect,
    "bGuest" => :b_guest,
    "bLocalRecordStatus" => :b_local_record,
    "bRaiseHand" => :hand_raised,
    "audioConnectionStatus" => :audio_connection_status,
    "action" => :action,
    "nUserStatus" => :n_user_status,
    "bInFailover" => :b_in_failover,
    "bid" => :bid
  }

  # Fields that are boolean (need == true coercion)
  @boolean_fields [
    :is_host,
    :is_cohost,
    :muted,
    :video_on,
    :b_hold,
    :b_share_on,
    :b_share_pause,
    :b_video_connect,
    :b_guest,
    :b_local_record,
    :hand_raised,
    :b_in_failover
  ]

  @doc "Parse all known fields from a raw roster entry, unknown keys go to raw_extra."
  @spec from_raw(map()) :: t()
  def from_raw(raw) when is_map(raw) do
    {known, extra} = split_known_fields(raw)

    struct =
      Enum.reduce(known, %__MODULE__{}, fn {raw_key, struct_field}, acc ->
        value = coerce_value(struct_field, raw_key, raw)
        Map.put(acc, struct_field, value)
      end)

    %{struct | raw_extra: extra}
  end

  @doc "Partially update an existing participant with only the fields present in raw data."
  @spec merge_update(t(), map()) :: t()
  def merge_update(%__MODULE__{} = existing, raw_update) when is_map(raw_update) do
    {known, new_extra} = split_known_fields(raw_update)

    updated =
      Enum.reduce(known, existing, fn {raw_key, struct_field}, acc ->
        value = coerce_value(struct_field, raw_key, raw_update)
        Map.put(acc, struct_field, value)
      end)

    merged_extra = Map.merge(existing.raw_extra, new_extra)
    %{updated | raw_extra: merged_extra}
  end

  @doc "Convert back to existing Participant struct for backward compatibility."
  @spec to_legacy(t()) :: ZoomGate.MeetingBot.Participant.t()
  def to_legacy(%__MODULE__{} = enriched) do
    %ZoomGate.MeetingBot.Participant{
      id: enriched.id,
      display_name: enriched.display_name,
      zoom_id: enriched.zoom_id,
      avatar: enriched.avatar,
      role: enriched.role,
      is_host: enriched.is_host,
      is_cohost: enriched.is_cohost,
      muted: enriched.muted,
      video_on: enriched.video_on,
      b_hold: enriched.b_hold
    }
  end

  # -- Private --

  defp split_known_fields(raw) do
    Enum.reduce(raw, {[], %{}}, fn {key, _value}, {known, extra} ->
      case Map.get(@field_map, key) do
        nil -> {known, Map.put(extra, key, raw[key])}
        struct_field -> {[{key, struct_field} | known], extra}
      end
    end)
  end

  defp coerce_value(:display_name, _raw_key, raw) do
    Protocol.b64_decode(raw["dn2"])
  end

  defp coerce_value(field, raw_key, raw) when field in @boolean_fields do
    raw[raw_key] == true
  end

  defp coerce_value(:role, raw_key, raw) do
    raw[raw_key] || 0
  end

  defp coerce_value(_field, raw_key, raw) do
    raw[raw_key]
  end
end
