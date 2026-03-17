defmodule ZoomGate.ApiSpec do
  @moduledoc """
  OpenAPI 3.0 specification for ZoomGate's REST API.

  Defines all endpoints, request/response schemas, and security schemes
  programmatically using `OpenApiSpex`. Since the router is a `Plug.Router`
  (not Phoenix controllers), the full spec is built inline here.

  ## Usage

      # Get the spec as a map
      ZoomGate.ApiSpec.spec()

      # Generate JSON file
      mix openapi
  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the complete OpenAPI 3.0 specification as a map.
  """
  @spec spec() :: map()
  def spec do
    %{
      "openapi" => "3.0.3",
      "info" => info(),
      "servers" => servers(),
      "security" => [%{"bearerAuth" => []}],
      "paths" => paths(),
      "components" => components()
    }
  end

  # -- Info --

  defp info do
    %{
      "title" => "ZoomGate API",
      "version" => @version,
      "description" =>
        "Zoom Meeting SDK bridge — waiting room access control as a service. " <>
          "ZoomGate connects to Zoom meetings as a bot and provides full control " <>
          "over waiting room admission, participant management, and in-meeting chat.",
      "contact" => %{
        "name" => "ZoomGate",
        "url" => "https://github.com/jhlee111/zoom_gate"
      },
      "license" => %{
        "name" => "MIT",
        "url" => "https://opensource.org/licenses/MIT"
      }
    }
  end

  defp servers do
    [
      %{"url" => "http://localhost:4000", "description" => "Local development"},
      %{"url" => "https://zoomgate.example.com", "description" => "Production"}
    ]
  end

  # -- Components --

  defp components do
    %{
      "securitySchemes" => %{
        "bearerAuth" => %{
          "type" => "http",
          "scheme" => "bearer",
          "description" =>
            "API key passed as Bearer token. If no api_key is configured on the server, " <>
              "authentication is disabled and all requests pass through."
        }
      },
      "schemas" => schemas(),
      "responses" => common_responses()
    }
  end

  defp schemas do
    %{
      # -- Shared --
      "Participant" => participant_schema(),
      "ParticipantMap" => participant_map_schema(),
      "ErrorResponse" => error_response_schema(),
      "StatusOk" => status_ok_schema(),

      # -- Session lifecycle --
      "CreateSessionRequest" => create_session_request_schema(),
      "CreateSessionResponse" => create_session_response_schema(),
      "ListSessionsResponse" => list_sessions_response_schema(),
      "SessionStatusResponse" => session_status_response_schema(),
      "LeaveSessionResponse" => leave_session_response_schema(),

      # -- Participant queries --
      "ParticipantsResponse" => participants_response_schema(),
      "WaitingRoomResponse" => waiting_room_response_schema(),

      # -- Commands --
      "AdmitRequest" => admit_request_schema(),
      "DenyRequest" => deny_request_schema(),
      "RenameRequest" => rename_request_schema(),
      "ExpelRequest" => expel_request_schema(),
      "ChatRequest" => chat_request_schema(),
      "ChatWaitingRoomRequest" => chat_waiting_room_request_schema(),
      "MuteRequest" => mute_request_schema(),

      # -- Health --
      "HealthResponse" => health_response_schema()
    }
  end

  defp common_responses do
    %{
      "NotFound" => %{
        "description" => "Session not found",
        "content" => %{
          "application/json" => %{
            "schema" => %{"$ref" => "#/components/schemas/ErrorResponse"}
          }
        }
      },
      "Unauthorized" => %{
        "description" => "Invalid or missing Bearer token",
        "content" => %{
          "application/json" => %{
            "schema" => %{"$ref" => "#/components/schemas/ErrorResponse"},
            "example" => %{"error" => "unauthorized"}
          }
        }
      }
    }
  end

  # -- Schema definitions --

  defp participant_schema do
    %{
      "type" => "object",
      "description" => "A meeting participant or waiting room entry.",
      "properties" => %{
        "zoom_user_id" => %{
          "type" => "integer",
          "description" => "Zoom user ID (changes on admit from waiting room)"
        },
        "display_name" => %{"type" => "string", "description" => "Participant display name"},
        "role" => %{
          "type" => "integer",
          "description" => "Participant role (0=attendee, 1=host, 2=cohost)"
        },
        "is_host" => %{
          "type" => "boolean",
          "description" => "Whether the participant is the host"
        },
        "is_cohost" => %{
          "type" => "boolean",
          "description" => "Whether the participant is a co-host"
        },
        "muted" => %{
          "type" => "boolean",
          "description" => "Whether the participant's audio is muted"
        },
        "video_on" => %{
          "type" => "boolean",
          "description" => "Whether the participant's video is on"
        }
      }
    }
  end

  defp participant_map_schema do
    %{
      "type" => "object",
      "description" => "Map of zoom_user_id (as string key) to Participant objects.",
      "additionalProperties" => %{"$ref" => "#/components/schemas/Participant"}
    }
  end

  defp error_response_schema do
    %{
      "type" => "object",
      "required" => ["error"],
      "properties" => %{
        "error" => %{"type" => "string", "description" => "Error message"}
      }
    }
  end

  defp status_ok_schema do
    %{
      "type" => "object",
      "required" => ["status"],
      "properties" => %{
        "status" => %{"type" => "string", "enum" => ["ok"]}
      }
    }
  end

  # -- Session lifecycle schemas --

  defp create_session_request_schema do
    %{
      "type" => "object",
      "required" => ["meeting_id"],
      "properties" => %{
        "meeting_id" => %{"type" => "string", "description" => "Zoom meeting ID"},
        "sdk_key" => %{
          "type" => "string",
          "description" => "Zoom Meeting SDK key (overrides server config)"
        },
        "sdk_secret" => %{
          "type" => "string",
          "description" => "Zoom Meeting SDK secret (overrides server config)"
        },
        "meeting_password" => %{
          "type" => "string",
          "description" => "Meeting password if required"
        },
        "webhook_url" => %{
          "type" => "string",
          "format" => "uri",
          "description" => "URL for event delivery via HTTP POST"
        },
        "display_name" => %{
          "type" => "string",
          "description" => "Bot display name in the meeting"
        }
      }
    }
  end

  defp create_session_response_schema do
    %{
      "type" => "object",
      "required" => ["meeting_id", "status"],
      "properties" => %{
        "meeting_id" => %{"type" => "string", "description" => "Zoom meeting ID"},
        "status" => %{"type" => "string", "enum" => ["connecting"]}
      }
    }
  end

  defp list_sessions_response_schema do
    %{
      "type" => "object",
      "required" => ["sessions"],
      "properties" => %{
        "sessions" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "meeting_id" => %{"type" => "string"}
            }
          }
        }
      }
    }
  end

  defp session_status_response_schema do
    %{
      "type" => "object",
      "required" => ["meeting_id", "status", "participants", "waiting_room"],
      "properties" => %{
        "meeting_id" => %{"type" => "string", "description" => "Zoom meeting ID"},
        "status" => %{
          "type" => "string",
          "description" => "Session status",
          "enum" => ["connecting", "joined", "leaving", "ended"]
        },
        "participants" => %{"$ref" => "#/components/schemas/ParticipantMap"},
        "waiting_room" => %{"$ref" => "#/components/schemas/ParticipantMap"}
      }
    }
  end

  defp leave_session_response_schema do
    %{
      "type" => "object",
      "required" => ["status"],
      "properties" => %{
        "status" => %{"type" => "string", "enum" => ["left"]}
      }
    }
  end

  # -- Participant query schemas --

  defp participants_response_schema do
    %{
      "type" => "object",
      "required" => ["participants"],
      "properties" => %{
        "participants" => %{"$ref" => "#/components/schemas/ParticipantMap"}
      }
    }
  end

  defp waiting_room_response_schema do
    %{
      "type" => "object",
      "required" => ["waiting_room"],
      "properties" => %{
        "waiting_room" => %{"$ref" => "#/components/schemas/ParticipantMap"}
      }
    }
  end

  # -- Command request schemas --

  defp admit_request_schema do
    %{
      "type" => "object",
      "required" => ["zoom_user_id"],
      "properties" => %{
        "zoom_user_id" => %{"type" => "integer", "description" => "Zoom user ID to admit"},
        "display_name" => %{"type" => "string", "description" => "Optional display name override"}
      }
    }
  end

  defp deny_request_schema do
    %{
      "type" => "object",
      "required" => ["zoom_user_id"],
      "properties" => %{
        "zoom_user_id" => %{"type" => "integer", "description" => "Zoom user ID to deny"},
        "message" => %{
          "type" => "string",
          "description" => "Optional denial message shown to the user"
        }
      }
    }
  end

  defp rename_request_schema do
    %{
      "type" => "object",
      "required" => ["zoom_user_id", "display_name"],
      "properties" => %{
        "zoom_user_id" => %{"type" => "integer", "description" => "Zoom user ID to rename"},
        "display_name" => %{"type" => "string", "description" => "New display name"}
      }
    }
  end

  defp expel_request_schema do
    %{
      "type" => "object",
      "required" => ["zoom_user_id"],
      "properties" => %{
        "zoom_user_id" => %{
          "type" => "integer",
          "description" => "Zoom user ID to remove from the meeting"
        }
      }
    }
  end

  defp chat_request_schema do
    %{
      "type" => "object",
      "required" => ["message"],
      "properties" => %{
        "message" => %{"type" => "string", "description" => "Chat message text"},
        "to" => %{
          "type" => "integer",
          "description" => "Zoom user ID for private message (omit for broadcast)"
        }
      }
    }
  end

  defp chat_waiting_room_request_schema do
    %{
      "type" => "object",
      "required" => ["message"],
      "properties" => %{
        "message" => %{
          "type" => "string",
          "description" => "Message to send to all waiting room participants"
        }
      }
    }
  end

  defp mute_request_schema do
    %{
      "type" => "object",
      "required" => ["zoom_user_id"],
      "properties" => %{
        "zoom_user_id" => %{"type" => "integer", "description" => "Zoom user ID to mute"}
      }
    }
  end

  # -- Health schema --

  defp health_response_schema do
    %{
      "type" => "object",
      "required" => ["status", "sessions", "max_sessions"],
      "properties" => %{
        "status" => %{"type" => "string", "enum" => ["ok"]},
        "sessions" => %{"type" => "integer", "description" => "Current active session count"},
        "max_sessions" => %{"type" => "integer", "description" => "Maximum allowed sessions"}
      }
    }
  end

  # -- Paths --

  defp paths do
    %{
      "/health" => health_path(),
      "/api/sessions" => sessions_path(),
      "/api/sessions/{meeting_id}" => session_path(),
      "/api/sessions/{meeting_id}/participants" => participants_path(),
      "/api/sessions/{meeting_id}/waiting_room" => waiting_room_path(),
      "/api/sessions/{meeting_id}/admit" => admit_path(),
      "/api/sessions/{meeting_id}/deny" => deny_path(),
      "/api/sessions/{meeting_id}/admit_all" => admit_all_path(),
      "/api/sessions/{meeting_id}/rename" => rename_path(),
      "/api/sessions/{meeting_id}/expel" => expel_path(),
      "/api/sessions/{meeting_id}/chat" => chat_path(),
      "/api/sessions/{meeting_id}/chat_waiting_room" => chat_waiting_room_path(),
      "/api/sessions/{meeting_id}/mute" => mute_path(),
      "/api/sessions/{meeting_id}/end_meeting" => end_meeting_path()
    }
  end

  defp meeting_id_param do
    %{
      "name" => "meeting_id",
      "in" => "path",
      "required" => true,
      "description" => "Zoom meeting ID",
      "schema" => %{"type" => "string"}
    }
  end

  defp json_request(schema_ref, opts \\ []) do
    required = Keyword.get(opts, :required, true)

    %{
      "required" => required,
      "content" => %{
        "application/json" => %{
          "schema" => %{"$ref" => "#/components/schemas/#{schema_ref}"}
        }
      }
    }
  end

  defp json_response(schema_ref, description) do
    %{
      "description" => description,
      "content" => %{
        "application/json" => %{
          "schema" => %{"$ref" => "#/components/schemas/#{schema_ref}"}
        }
      }
    }
  end

  # -- Path definitions --

  defp health_path do
    %{
      "get" => %{
        "tags" => ["Health"],
        "summary" => "Health check",
        "description" =>
          "Returns server health status and session counts. No authentication required.",
        "operationId" => "getHealth",
        "security" => [],
        "responses" => %{
          "200" => json_response("HealthResponse", "Server is healthy")
        }
      }
    }
  end

  defp sessions_path do
    %{
      "post" => %{
        "tags" => ["Sessions"],
        "summary" => "Create a bot session",
        "description" =>
          "Starts a new ZoomGate bot that joins the specified Zoom meeting. " <>
            "The bot connects asynchronously — use the status endpoint or webhooks to track join progress.",
        "operationId" => "createSession",
        "requestBody" => json_request("CreateSessionRequest"),
        "responses" => %{
          "201" => json_response("CreateSessionResponse", "Session created, bot is connecting"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "422" =>
            json_response(
              "ErrorResponse",
              "Validation error (missing meeting_id or session already exists)"
            )
        }
      },
      "get" => %{
        "tags" => ["Sessions"],
        "summary" => "List active sessions",
        "description" => "Returns all currently active bot sessions.",
        "operationId" => "listSessions",
        "responses" => %{
          "200" => json_response("ListSessionsResponse", "List of active sessions"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"}
        }
      }
    }
  end

  defp session_path do
    %{
      "get" => %{
        "tags" => ["Sessions"],
        "summary" => "Get session status",
        "description" =>
          "Returns the full status of a session including participants and waiting room entries.",
        "operationId" => "getSession",
        "parameters" => [meeting_id_param()],
        "responses" => %{
          "200" => json_response("SessionStatusResponse", "Session status with participants"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      },
      "delete" => %{
        "tags" => ["Sessions"],
        "summary" => "Leave meeting",
        "description" => "Stops the bot session and leaves the Zoom meeting gracefully.",
        "operationId" => "deleteSession",
        "parameters" => [meeting_id_param()],
        "responses" => %{
          "200" => json_response("LeaveSessionResponse", "Bot has left the meeting"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp participants_path do
    %{
      "get" => %{
        "tags" => ["Participants"],
        "summary" => "List participants",
        "description" =>
          "Returns all active participants in the meeting (excludes waiting room).",
        "operationId" => "listParticipants",
        "parameters" => [meeting_id_param()],
        "responses" => %{
          "200" =>
            json_response("ParticipantsResponse", "Map of participants keyed by zoom_user_id"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp waiting_room_path do
    %{
      "get" => %{
        "tags" => ["Participants"],
        "summary" => "List waiting room",
        "description" => "Returns all participants currently in the waiting room.",
        "operationId" => "listWaitingRoom",
        "parameters" => [meeting_id_param()],
        "responses" => %{
          "200" =>
            json_response(
              "WaitingRoomResponse",
              "Map of waiting room entries keyed by zoom_user_id"
            ),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp admit_path do
    %{
      "post" => %{
        "tags" => ["Commands"],
        "summary" => "Admit from waiting room",
        "description" =>
          "Admits a participant from the waiting room into the meeting. " <>
            "Note: the participant's zoom_user_id will change after admission.",
        "operationId" => "admitParticipant",
        "parameters" => [meeting_id_param()],
        "requestBody" => json_request("AdmitRequest"),
        "responses" => %{
          "200" => json_response("StatusOk", "Admit command sent"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp deny_path do
    %{
      "post" => %{
        "tags" => ["Commands"],
        "summary" => "Deny from waiting room",
        "description" => "Denies a participant and removes them from the waiting room.",
        "operationId" => "denyParticipant",
        "parameters" => [meeting_id_param()],
        "requestBody" => json_request("DenyRequest"),
        "responses" => %{
          "200" => json_response("StatusOk", "Deny command sent"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp admit_all_path do
    %{
      "post" => %{
        "tags" => ["Commands"],
        "summary" => "Admit all from waiting room",
        "description" =>
          "Admits all participants currently in the waiting room into the meeting.",
        "operationId" => "admitAll",
        "parameters" => [meeting_id_param()],
        "requestBody" => %{
          "required" => false,
          "content" => %{
            "application/json" => %{
              "schema" => %{"type" => "object"}
            }
          }
        },
        "responses" => %{
          "200" => json_response("StatusOk", "Admit all command sent"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp rename_path do
    %{
      "post" => %{
        "tags" => ["Commands"],
        "summary" => "Rename participant",
        "description" => "Changes the display name of a participant in the meeting.",
        "operationId" => "renameParticipant",
        "parameters" => [meeting_id_param()],
        "requestBody" => json_request("RenameRequest"),
        "responses" => %{
          "200" => json_response("StatusOk", "Rename command sent"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp expel_path do
    %{
      "post" => %{
        "tags" => ["Commands"],
        "summary" => "Remove participant",
        "description" => "Removes (kicks) a participant from the meeting entirely.",
        "operationId" => "expelParticipant",
        "parameters" => [meeting_id_param()],
        "requestBody" => json_request("ExpelRequest"),
        "responses" => %{
          "200" => json_response("StatusOk", "Expel command sent"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp chat_path do
    %{
      "post" => %{
        "tags" => ["Commands"],
        "summary" => "Send chat message",
        "description" =>
          "Sends a chat message in the meeting. " <>
            "Omit 'to' for a broadcast message, or specify a zoom_user_id for a private message.",
        "operationId" => "sendChat",
        "parameters" => [meeting_id_param()],
        "requestBody" => json_request("ChatRequest"),
        "responses" => %{
          "200" => json_response("StatusOk", "Chat message sent"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp chat_waiting_room_path do
    %{
      "post" => %{
        "tags" => ["Commands"],
        "summary" => "Chat to waiting room",
        "description" =>
          "Sends a chat message to all participants in the waiting room. " <>
            "Uses destNodeID=4 (SilentModeUsers).",
        "operationId" => "chatWaitingRoom",
        "parameters" => [meeting_id_param()],
        "requestBody" => json_request("ChatWaitingRoomRequest"),
        "responses" => %{
          "200" => json_response("StatusOk", "Chat message sent to waiting room"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp mute_path do
    %{
      "post" => %{
        "tags" => ["Commands"],
        "summary" => "Mute participant",
        "description" => "Mutes a participant's audio in the meeting.",
        "operationId" => "muteParticipant",
        "parameters" => [meeting_id_param()],
        "requestBody" => json_request("MuteRequest"),
        "responses" => %{
          "200" => json_response("StatusOk", "Mute command sent"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end

  defp end_meeting_path do
    %{
      "post" => %{
        "tags" => ["Commands"],
        "summary" => "End meeting",
        "description" => "Ends the meeting for all participants. Requires host privileges.",
        "operationId" => "endMeeting",
        "parameters" => [meeting_id_param()],
        "requestBody" => %{
          "required" => false,
          "content" => %{
            "application/json" => %{
              "schema" => %{"type" => "object"}
            }
          }
        },
        "responses" => %{
          "200" => json_response("StatusOk", "End meeting command sent"),
          "401" => %{"$ref" => "#/components/responses/Unauthorized"},
          "404" => %{"$ref" => "#/components/responses/NotFound"}
        }
      }
    }
  end
end
