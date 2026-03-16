#!/usr/bin/env python3
"""Mock Zoom SDK worker for testing ZoomGate on ARM64 (no real SDK available).

Protocol: newline-delimited JSON over stdin/stdout.

On startup: emits {"event":"joined"}
Commands:
  admit → participant_joined
  deny  → waiting_room_leave
  expel → participant_left
  leave → meeting_ended + exit(0)
  simulate → emit arbitrary event_data
  crash → exit(non-zero)
"""

import json
import signal
import sys

# Suppress BrokenPipeError when port is closed
signal.signal(signal.SIGPIPE, signal.SIG_DFL)


def emit(event):
    try:
        sys.stdout.write(json.dumps(event) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        sys.exit(0)


def main():
    emit({"event": "joined"})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            cmd = json.loads(line)
        except json.JSONDecodeError:
            emit({"event": "error", "code": -1, "message": "invalid JSON"})
            continue

        command = cmd.get("command")

        if command == "admit":
            emit({
                "event": "participant_joined",
                "zoom_user_id": cmd["zoom_user_id"],
                "display_name": cmd.get("display_name", "User"),
            })
        elif command == "deny":
            emit({
                "event": "waiting_room_leave",
                "zoom_user_id": cmd["zoom_user_id"],
            })
        elif command == "expel":
            emit({
                "event": "participant_left",
                "zoom_user_id": cmd["zoom_user_id"],
            })
        elif command == "rename":
            pass  # No SDK response for rename
        elif command == "chat":
            pass  # No SDK response for chat
        elif command == "leave":
            emit({"event": "meeting_ended"})
            sys.exit(0)
        elif command == "simulate":
            emit(cmd.get("event_data", {}))
        elif command == "crash":
            sys.exit(cmd.get("exit_code", 1))
        else:
            emit({"event": "error", "code": -1, "message": f"unknown command: {command}"})


if __name__ == "__main__":
    main()
