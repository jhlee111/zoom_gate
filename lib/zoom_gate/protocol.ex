defmodule ZoomGate.Protocol do
  @moduledoc """
  Message protocol between ZoomGate and the C++ SDK worker.

  All messages are newline-delimited JSON over stdin/stdout.

  ## Commands (Elixir → C++ worker via stdin)

      {"command": "join", "meeting_id": "123", "sdk_key": "...", "sdk_secret": "..."}
      {"command": "admit", "zoom_user_id": 12345, "display_name": "홍길동 (강남)"}
      {"command": "deny", "zoom_user_id": 12345, "message": "Not authorized"}
      {"command": "rename", "zoom_user_id": 12345, "display_name": "New Name"}
      {"command": "expel", "zoom_user_id": 12345}
      {"command": "chat", "message": "Hello everyone", "to": 12345}
      {"command": "leave"}

  ## Events (C++ worker → Elixir via stdout)

      {"event": "joined"}
      {"event": "waiting_room_join", "zoom_user_id": 12345, "display_name": "John", "email": "j@x.com"}
      {"event": "waiting_room_leave", "zoom_user_id": 12345}
      {"event": "participant_joined", "zoom_user_id": 12345, "display_name": "John"}
      {"event": "participant_left", "zoom_user_id": 12345}
      {"event": "meeting_ended"}
      {"event": "error", "code": 1234, "message": "SDK error description"}

  ## Design Principles

  - One JSON object per line (newline-delimited)
  - Worker is stateless I/O — zero business logic
  - Worker crashes are detected via Port exit_status
  - All string values are UTF-8
  """

  @type command ::
          :join
          | :admit
          | :deny
          | :rename
          | :expel
          | :chat
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
end
