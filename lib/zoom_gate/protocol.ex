defmodule ZoomGate.Protocol do
  @moduledoc """
  Message protocol between ZoomGate and the C++ SDK worker.

  All messages are newline-delimited JSON over stdin/stdout.

  ## Commands (Elixir → C++ worker via stdin)

      {"command": "admit", "zoom_user_id": 12345, "display_name": "홍길동 (강남)"}
      {"command": "deny", "zoom_user_id": 12345, "message": "Not authorized"}
      {"command": "rename", "zoom_user_id": 12345, "display_name": "New Name"}
      {"command": "expel", "zoom_user_id": 12345}
      {"command": "chat", "message": "Hello everyone", "to": 12345}
      {"command": "chat_waiting_room", "message": "안녕하세요, 성함을 확인해주세요"}
      {"command": "leave"}

  ## Events (C++ worker → Elixir via stdout)

      {"event": "joined"}
      {"event": "waiting_room_join", "zoom_user_id": 12345, "display_name": "John", "email": "j@x.com"}
      {"event": "waiting_room_leave", "zoom_user_id": 12345}
      {"event": "participant_joined", "zoom_user_id": 12345, "display_name": "John"}
      {"event": "participant_left", "zoom_user_id": 12345}
      {"event": "meeting_ended"}
      {"event": "error", "code": 1234, "message": "SDK error description"}
  """

  @valid_commands ~w(join admit admit_all deny rename expel mute unmute chat chat_waiting_room put_on_hold make_host make_cohost list_participants get_current_user end_meeting leave)
  @valid_events ~w(ready joined left waiting_room_join waiting_room_leave participant_joined participant_left meeting_ended error command_ok user_updated participants current_user chat_received)

  @type command ::
          :admit
          | :deny
          | :rename
          | :expel
          | :chat
          | :chat_waiting_room
          | :leave

  @type event ::
          :joined
          | :waiting_room_join
          | :waiting_room_leave
          | :participant_joined
          | :participant_left
          | :meeting_ended
          | :error

  @doc """
  Encodes a command map to a newline-terminated JSON string.
  """
  @spec encode_command(map()) :: binary()
  def encode_command(command) when is_map(command) do
    Jason.encode!(command) <> "\n"
  end

  @doc """
  Decodes a JSON line from the worker into an event map.
  """
  @spec decode_event(binary()) :: {:ok, map()} | {:error, term()}
  def decode_event(line) when is_binary(line) do
    line
    |> String.trim()
    |> Jason.decode()
  end

  @doc "Returns true if the given command name string is valid."
  def valid_command?(name) when name in @valid_commands, do: true
  def valid_command?(_), do: false

  @doc "Returns true if the given event name string is valid."
  def valid_event?(name) when name in @valid_events, do: true
  def valid_event?(_), do: false
end
