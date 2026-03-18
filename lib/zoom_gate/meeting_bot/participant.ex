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
      is_cohost: raw["isCoHost"] == true,
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
    {participants, events} = process_adds(participants, Map.get(body, "add", []))
    {participants, events2} = process_updates(participants, Map.get(body, "update", []))
    {participants, events3} = process_removes(participants, Map.get(body, "remove", []))
    {participants, events ++ events2 ++ events3}
  end

  @doc "Split participants into active and waiting room maps."
  @spec split_by_hold(map()) :: {map(), map()}
  def split_by_hold(participants) do
    Enum.split_with(participants, fn {_id, p} -> not p.b_hold end)
    |> then(fn {active, waiting} ->
      {Map.new(active), Map.new(waiting)}
    end)
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

  # -- Internal --

  defp process_adds(participants, adds) when is_list(adds) do
    Enum.reduce(adds, {participants, []}, fn raw, {ps, evts} ->
      p = from_raw(raw)
      event_type = if p.b_hold, do: :waiting_room_join, else: :participant_joined
      {Map.put(ps, p.id, p), evts ++ [{event_type, to_event_map(p)}]}
    end)
  end

  defp process_adds(participants, _), do: {participants, []}

  defp process_updates(participants, updates) when is_list(updates) do
    Enum.reduce(updates, {participants, []}, fn raw, {ps, evts} ->
      apply_update(ps, evts, raw)
    end)
  end

  defp process_updates(participants, _), do: {participants, []}

  defp apply_update(ps, evts, raw) do
    id = raw["id"]
    new_data = from_raw(raw)

    case Map.get(ps, id) do
      nil ->
        event_type = if new_data.b_hold, do: :waiting_room_join, else: :participant_joined
        {Map.put(ps, id, new_data), evts ++ [{event_type, to_event_map(new_data)}]}

      existing ->
        merged = merge_fields(existing, new_data, raw)
        update_evts = diff_events(existing, merged)
        {Map.put(ps, id, merged), evts ++ update_evts}
    end
  end

  defp process_removes(participants, removes) when is_list(removes) do
    Enum.reduce(removes, {participants, []}, fn raw, {ps, evts} ->
      apply_remove(ps, evts, raw)
    end)
  end

  defp process_removes(participants, _), do: {participants, []}

  defp apply_remove(ps, evts, raw) do
    id = raw["id"]

    case Map.get(ps, id) do
      nil ->
        {ps, evts}

      existing ->
        event_type = if existing.b_hold, do: :waiting_room_leave, else: :participant_left
        {Map.delete(ps, id), evts ++ [{event_type, %{zoom_user_id: id}}]}
    end
  end

  defp merge_fields(existing, new_data, raw) do
    # Only update fields that are actually present in the raw data
    existing
    |> maybe_update(:display_name, new_data.display_name, raw["dn2"])
    |> maybe_update(:role, new_data.role, raw["role"])
    |> maybe_update(:is_host, new_data.is_host, raw["isHost"])
    |> maybe_update(:is_cohost, new_data.is_cohost, raw["isCoHost"])
    |> maybe_update(:muted, new_data.muted, raw["muted"])
    |> maybe_update(:video_on, new_data.video_on, raw["bVideoOn"])
    |> maybe_update(:b_hold, new_data.b_hold, raw["bHold"])
    |> maybe_update(:avatar, new_data.avatar, raw["avatar"])
  end

  defp diff_events(old, new) do
    evts = []

    evts =
      if old.display_name != new.display_name and new.display_name != "" do
        evts ++
          [
            {:participant_renamed,
             %{
               zoom_user_id: new.id,
               old_name: old.display_name,
               new_name: new.display_name
             }}
          ]
      else
        evts
      end

    evts =
      if old.b_hold != new.b_hold do
        if new.b_hold do
          evts ++ [{:waiting_room_join, to_event_map(new)}]
        else
          evts ++ [{:waiting_room_leave, %{zoom_user_id: new.id}}]
        end
      else
        evts
      end

    evts
  end

  defp maybe_update(participant, _field, _value, nil), do: participant
  defp maybe_update(participant, field, value, _raw), do: Map.put(participant, field, value)
end
