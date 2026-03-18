defmodule ZoomGate.Analyzer.ClientState do
  @moduledoc """
  Complete client state tree for a Zoom meeting session.

  This is a pure data structure with pure transition functions — no processes,
  no side effects. It models the same state that a native Zoom client would maintain:
  participants, meeting settings, chat history, and self identity.

  The core function `apply_event/2` is a pure reducer that takes the current state
  and a decoded RWG event, returning the new state plus a list of change descriptors.
  """

  alias ZoomGate.Analyzer.{EnrichedParticipant, MeetingSettings, ChatMessage}

  defstruct [
    :meeting_number,
    :self_user_id,
    :self_participant_id,
    :self_zoom_id,
    :self_role,
    :meeting_token,
    :last_updated_at,
    status: :disconnected,
    participants: %{},
    meeting_settings: %MeetingSettings{},
    chat_history: []
  ]

  @type t :: %__MODULE__{}

  @type change ::
          {:status_changed, atom(), atom()}
          | {:participant_added, map()}
          | {:participant_updated, map()}
          | {:participant_removed, map()}
          | {:setting_changed, atom(), any(), any()}
          | {:chat_received, map()}
          | {:host_changed, map()}
          | {:cohost_changed, map()}
          | {:options_changed, map()}
          | {:unknown_event, integer(), map()}

  @doc "Create initial state for a meeting."
  @spec new(String.t()) :: t()
  def new(meeting_number) do
    %__MODULE__{
      meeting_number: meeting_number,
      meeting_settings: MeetingSettings.new()
    }
  end

  @doc """
  Apply a decoded RWG event to the state.

  Returns `{new_state, changes}` where changes is a list of change descriptors
  that describe what changed for observers.
  """
  @spec apply_event(t(), map()) :: {t(), [change()]}
  def apply_event(state, %{"evt" => evt, "body" => body}) do
    {new_state, changes} = handle_event(state, evt, body)
    {%{new_state | last_updated_at: DateTime.utc_now()}, changes}
  end

  def apply_event(state, _), do: {state, []}

  # -- Event Handlers --

  # Keepalive (evt 0)
  defp handle_event(state, 0, _body), do: {state, []}

  # Join response (evt 4098)
  defp handle_event(state, 4098, %{"res" => 0} = body) do
    new_state = %{
      state
      | status: :active,
        self_user_id: body["userID"],
        self_zoom_id: body["zoomID"],
        self_participant_id: body["participantID"],
        self_role: body["role"],
        meeting_token: body["meetingtoken"]
    }

    {new_state, [{:status_changed, state.status, :active}]}
  end

  defp handle_event(state, 4098, _body) do
    new_state = %{state | status: :ended}
    {new_state, [{:status_changed, state.status, :ended}]}
  end

  # Roster update (evt 7937)
  defp handle_event(state, 7937, body) do
    {participants, changes} =
      state.participants
      |> process_roster_adds(Map.get(body, "add", []))
      |> process_roster_updates(Map.get(body, "update", []))
      |> process_roster_removes(Map.get(body, "remove", []))

    {%{state | participants: participants}, changes}
  end

  # Meeting settings (evt 7938)
  defp handle_event(state, 7938, body) do
    {new_settings, changed_fields} = MeetingSettings.merge(state.meeting_settings, body)

    changes =
      Enum.map(changed_fields, fn field ->
        old_val = Map.get(state.meeting_settings, field)
        new_val = Map.get(new_settings, field)
        {:setting_changed, field, old_val, new_val}
      end)

    {%{state | meeting_settings: new_settings}, changes}
  end

  # Meeting ended (evt 7939)
  defp handle_event(state, 7939, _body) do
    new_state = %{state | status: :ended}
    {new_state, [{:status_changed, state.status, :ended}]}
  end

  # Host change (evt 7940)
  defp handle_event(state, 7940, body) do
    {state, [{:host_changed, body}]}
  end

  # Co-host change (evt 7941)
  defp handle_event(state, 7941, body) do
    {state, [{:cohost_changed, body}]}
  end

  # Self hold status change (evt 7942)
  defp handle_event(state, 7942, %{"bHold" => true}) do
    new_state = %{state | status: :waiting_room}
    {new_state, [{:status_changed, state.status, :waiting_room}]}
  end

  defp handle_event(state, 7942, %{"bHold" => false}) do
    new_state = %{state | status: :active}
    {new_state, [{:status_changed, state.status, :active}]}
  end

  # Chat indication (evt 7944)
  defp handle_event(state, 7944, body) do
    msg = ChatMessage.from_incoming(body)
    new_state = %{state | chat_history: state.chat_history ++ [msg]}
    {new_state, [{:chat_received, %{msg_id: msg.msg_id}}]}
  end

  # Meeting options (evt 7945)
  defp handle_event(state, 7945, body) do
    {state, [{:options_changed, body}]}
  end

  # Unknown event — record it for protocol discovery
  defp handle_event(state, evt, body) do
    {state, [{:unknown_event, evt, body}]}
  end

  # -- Roster Processing (EnrichedParticipant) --

  defp process_roster_adds(participants, adds) when is_list(adds) do
    Enum.reduce(adds, {participants, []}, fn raw, {ps, changes} ->
      p = EnrichedParticipant.from_raw(raw)
      {Map.put(ps, p.id, p), changes ++ [{:participant_added, %{id: p.id, participant: p}}]}
    end)
  end

  defp process_roster_adds(participants, _), do: {participants, []}

  defp process_roster_updates({participants, changes}, updates) when is_list(updates) do
    Enum.reduce(updates, {participants, changes}, fn raw, {ps, ch} ->
      id = raw["id"]

      case Map.get(ps, id) do
        nil ->
          p = EnrichedParticipant.from_raw(raw)
          {Map.put(ps, p.id, p), ch ++ [{:participant_added, %{id: p.id, participant: p}}]}

        existing ->
          merged = EnrichedParticipant.merge_update(existing, raw)
          update_changes = diff_participant(existing, merged)
          {Map.put(ps, id, merged), ch ++ update_changes}
      end
    end)
  end

  defp process_roster_updates({participants, changes}, _), do: {participants, changes}

  defp process_roster_removes({participants, changes}, removes) when is_list(removes) do
    Enum.reduce(removes, {participants, changes}, fn raw, {ps, ch} ->
      id = raw["id"]

      case Map.get(ps, id) do
        nil ->
          {ps, ch}

        _existing ->
          {Map.delete(ps, id), ch ++ [{:participant_removed, %{id: id}}]}
      end
    end)
  end

  defp process_roster_removes({participants, changes}, _), do: {participants, changes}

  defp diff_participant(old, new) do
    changed_fields =
      [:display_name, :muted, :video_on, :b_hold, :is_host, :is_cohost, :b_share_on, :hand_raised]
      |> Enum.filter(fn field -> Map.get(old, field) != Map.get(new, field) end)

    if changed_fields == [] do
      []
    else
      [{:participant_updated, %{id: new.id, changed_fields: changed_fields, participant: new}}]
    end
  end
end
