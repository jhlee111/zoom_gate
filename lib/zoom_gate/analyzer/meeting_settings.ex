defmodule ZoomGate.Analyzer.MeetingSettings do
  @moduledoc """
  Complete meeting settings state from evt 7938 attribute updates.

  Tracks all known meeting configuration fields. Unknown fields are
  captured in `raw_extra` for protocol discovery.
  """

  defstruct [
    :b_lock,
    :b_hold_upon_entry,
    :view_only,
    :chat_priviledge,
    :panelist_chat_priviledge,
    :b_muted_all,
    :b_muted_upon_entry,
    :b_can_unmute,
    :b_allow_raise_hand,
    :b_allow_attendee_rename,
    :b_allow_attendee_chat,
    :encrypt_key,
    :gateway_key,
    raw_extra: %{}
  ]

  @type t :: %__MODULE__{}

  # Map of raw JSON field names to struct field names
  @field_map %{
    "bLock" => :b_lock,
    "bHoldUponEntry" => :b_hold_upon_entry,
    "viewOnly" => :view_only,
    "chatPriviledge" => :chat_priviledge,
    "panelistChatPriviledge" => :panelist_chat_priviledge,
    "bMutedAll" => :b_muted_all,
    "bMutedUponEntry" => :b_muted_upon_entry,
    "bCanUnmute" => :b_can_unmute,
    "bAllowRaiseHand" => :b_allow_raise_hand,
    "bAllowAttendeeRename" => :b_allow_attendee_rename,
    "bAllowAttendeeChat" => :b_allow_attendee_chat,
    "encryptKey" => :encrypt_key,
    "gatewayKey" => :gateway_key
  }

  @doc "Create empty settings."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Merge a partial settings update from evt 7938 body.

  Returns `{updated_settings, changed_field_names}` where changed_field_names
  is a list of atoms for fields that actually changed value.
  """
  @spec merge(t(), map()) :: {t(), [atom()]}
  def merge(%__MODULE__{} = settings, body) when is_map(body) do
    {updated, changed, new_extra} =
      Enum.reduce(body, {settings, [], %{}}, fn {raw_key, value}, {s, ch, ex} ->
        case Map.get(@field_map, raw_key) do
          nil ->
            {s, ch, Map.put(ex, raw_key, value)}

          struct_field ->
            old_value = Map.get(s, struct_field)

            if old_value != value do
              {Map.put(s, struct_field, value), [struct_field | ch], ex}
            else
              {s, ch, ex}
            end
        end
      end)

    merged_extra = Map.merge(settings.raw_extra, new_extra)
    {%{updated | raw_extra: merged_extra}, Enum.reverse(changed)}
  end
end
