defmodule ZoomGate.MeetingBot.Participant do
  @moduledoc """
  Participant state tracking for Zoom RWG sessions.

  Maintains a single participants map keyed by user ID. The `b_hold` field
  distinguishes waiting room participants (true) from active participants (false).
  """

  alias ZoomGate.MeetingBot.Protocol

  defstruct [
    :id,
    :display_name,
    :zoom_id,
    :avatar,
    role: 0,
    is_host: false,
    is_cohost: false,
    muted: false,
    video_on: false,
    b_hold: false
  ]

  @type t :: %__MODULE__{
          id: integer(),
          display_name: String.t(),
          zoom_id: String.t() | nil,
          avatar: String.t() | nil,
          role: integer(),
          is_host: boolean(),
          is_cohost: boolean(),
          muted: boolean(),
          video_on: boolean(),
          b_hold: boolean()
        }

  @tracked_fields [:display_name, :role, :is_host, :is_cohost, :muted, :video_on, :b_hold]

  @doc "Parse a participant from a raw roster entry map."
  @spec from_raw(map()) :: t()
  def from_raw(raw) when is_map(raw) do
    %__MODULE__{
      id: raw["id"],
      display_name: Protocol.b64_decode(raw["dn2"]),
      zoom_id: raw["zoomID"],
      avatar: raw["avatar"],
      role: raw["role"] || 0,
      is_host: raw["isHost"] == true,
      is_cohost: raw["isCoHost"] == true || raw["bCoHost"] == true,
      muted: raw["muted"] == true,
      video_on: raw["bVideoOn"] == true,
      b_hold: raw["bHold"] == true
    }
  end

  @doc """
  Merge a roster update into the participants map.

  Processes `add`, `update`, and `remove` lists from a roster body.
  Returns `{updated_participants, events}` where events is a list of
  `{event_type, payload}` tuples to emit.
  """
  @spec merge_roster(map(), map()) :: {map(), [{atom(), map()}]}
  def merge_roster(participants, body) when is_map(participants) and is_map(body) do
    {participants, []}
    |> process_entries(:add, body["add"])
    |> process_entries(:update, body["update"])
    |> process_entries(:remove, body["remove"])
  end

  @doc "Split participants into active and waiting room maps."
  @spec split_by_hold(map()) :: {map(), map()}
  def split_by_hold(participants) do
    {active, waiting} = Enum.split_with(participants, fn {_id, p} -> not p.b_hold end)
    {Map.new(active), Map.new(waiting)}
  end

  @doc "Convert a Participant to the map format used in Session events."
  @spec to_event_map(t()) :: map()
  def to_event_map(%__MODULE__{} = p) do
    %{
      zoom_user_id: p.id,
      display_name: p.display_name,
      role: p.role,
      is_host: p.is_host,
      is_cohost: p.is_cohost,
      muted: p.muted,
      video_on: p.video_on
    }
  end

  # -- Roster Processing --

  defp process_entries(acc, _action, nil), do: acc
  defp process_entries(acc, _action, entries) when not is_list(entries), do: acc

  defp process_entries(acc, action, entries) do
    Enum.reduce(entries, acc, fn raw, {ps, evts} ->
      apply_entry(action, ps, evts, raw)
    end)
  end

  defp apply_entry(:add, ps, evts, raw) do
    p = from_raw(raw)
    {Map.put(ps, p.id, p), evts ++ [{join_event_type(p), to_event_map(p)}]}
  end

  defp apply_entry(:update, ps, evts, raw) do
    id = raw["id"]
    new_data = from_raw(raw)

    case Map.fetch(ps, id) do
      {:ok, existing} ->
        merged = merge_fields(existing, new_data, raw)
        {Map.put(ps, id, merged), evts ++ diff_events(existing, merged)}

      :error ->
        {Map.put(ps, id, new_data), evts ++ [{join_event_type(new_data), to_event_map(new_data)}]}
    end
  end

  defp apply_entry(:remove, ps, evts, %{"id" => id}) do
    case Map.pop(ps, id) do
      {nil, ps} -> {ps, evts}
      {existing, ps} -> {ps, evts ++ [{leave_event_type(existing), %{zoom_user_id: id}}]}
    end
  end

  defp apply_entry(:remove, ps, evts, _), do: {ps, evts}

  # -- Event Type Resolution --

  defp join_event_type(%{b_hold: true}), do: :waiting_room_join
  defp join_event_type(%{b_hold: false}), do: :participant_joined

  defp leave_event_type(%{b_hold: true}), do: :waiting_room_leave
  defp leave_event_type(%{b_hold: false}), do: :participant_left

  # -- Field Merging --

  defp merge_fields(existing, new_data, raw) do
    existing
    |> maybe_update(:display_name, new_data.display_name, raw["dn2"])
    |> maybe_update(:role, new_data.role, raw["role"])
    |> maybe_update(:is_host, new_data.is_host, raw["isHost"])
    |> maybe_update(:is_cohost, new_data.is_cohost, raw["isCoHost"] || raw["bCoHost"])
    |> maybe_update(:muted, new_data.muted, raw["muted"])
    |> maybe_update(:video_on, new_data.video_on, raw["bVideoOn"])
    |> maybe_update(:b_hold, new_data.b_hold, raw["bHold"])
    |> maybe_update(:avatar, new_data.avatar, raw["avatar"])
  end

  defp maybe_update(participant, _field, _value, nil), do: participant
  defp maybe_update(participant, field, value, _raw), do: Map.put(participant, field, value)

  # -- Diff Events --

  defp diff_events(old, new) do
    [
      diff_hold(old, new),
      diff_rename(old, new),
      diff_tracked(old, new)
    ]
    |> List.flatten()
  end

  defp diff_hold(%{b_hold: same}, %{b_hold: same}), do: []
  defp diff_hold(_old, %{b_hold: true} = new), do: [{:waiting_room_join, to_event_map(new)}]
  defp diff_hold(_old, new), do: [{:waiting_room_leave, %{zoom_user_id: new.id}}]

  defp diff_rename(%{display_name: same}, %{display_name: same}), do: []
  defp diff_rename(_old, %{display_name: ""}), do: []

  defp diff_rename(old, new) do
    [
      {:participant_renamed,
       %{zoom_user_id: new.id, old_name: old.display_name, new_name: new.display_name}}
    ]
  end

  defp diff_tracked(old, new) do
    changes =
      @tracked_fields
      |> Enum.filter(fn field -> Map.get(old, field) != Map.get(new, field) end)
      |> Map.new(fn field -> {field, Map.get(new, field)} end)

    case map_size(changes) do
      0 -> []
      _ -> [{:participant_updated, Map.merge(%{zoom_user_id: new.id}, changes)}]
    end
  end
end
