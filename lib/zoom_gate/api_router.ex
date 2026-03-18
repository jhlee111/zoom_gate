defmodule ZoomGate.ApiRouter do
  @moduledoc """
  REST API router for ZoomGate session management.

  All endpoints require Bearer token authentication (see `ZoomGate.Plugs.ApiAuth`).

  ## Endpoints

      POST   /sessions                                Create bot session (join meeting)
      GET    /sessions                                List active sessions
      GET    /sessions/:meeting_id                    Get session status
      DELETE /sessions/:meeting_id                    Stop session (leave meeting)
      GET    /sessions/:meeting_id/participants       List active participants
      GET    /sessions/:meeting_id/waiting_room       List waiting room participants
      POST   /sessions/:meeting_id/admit              Admit from waiting room
      POST   /sessions/:meeting_id/deny               Deny and remove from waiting room
      POST   /sessions/:meeting_id/admit_all          Admit all from waiting room
      POST   /sessions/:meeting_id/rename             Rename participant
      POST   /sessions/:meeting_id/expel              Remove from meeting
      POST   /sessions/:meeting_id/chat               Send chat message
      POST   /sessions/:meeting_id/chat_waiting_room  Chat to waiting room (destNodeID=4)
      POST   /sessions/:meeting_id/mute               Mute a participant
      POST   /sessions/:meeting_id/end_meeting        End meeting for all
      POST   /sessions/:meeting_id/start_recording    Start cloud recording
      POST   /sessions/:meeting_id/stop_recording     Stop cloud recording
      POST   /sessions/:meeting_id/lock_sharing        Lock/unlock screen sharing
      POST   /sessions/:meeting_id/spotlight           Spotlight a participant

  ## Error Responses

  All errors return JSON:

      {"error": "description"}

  | Status | Meaning |
  |--------|---------|
  | 401 | Invalid or missing Bearer token |
  | 404 | Session not found |
  | 422 | Validation error (e.g., missing `meeting_id`) |

  ## Authentication

  Include `Authorization: Bearer <api_key>` header. If no API key is configured
  on the server, authentication is skipped.
  """

  use Plug.Router

  plug(:match)
  plug(ZoomGate.Plugs.ApiAuth)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  # -- Session lifecycle --

  post "/sessions" do
    meeting_id = conn.body_params["meeting_id"]

    if meeting_id do
      opts =
        [
          sdk_key: conn.body_params["sdk_key"] || "",
          sdk_secret: conn.body_params["sdk_secret"] || "",
          meeting_password: conn.body_params["meeting_password"] || ""
        ]
        |> maybe_put(:webhook_url, conn.body_params["webhook_url"])
        |> maybe_put(:display_name, conn.body_params["display_name"])

      case ZoomGate.SessionSupervisor.join_meeting(meeting_id, opts) do
        {:ok, _pid} ->
          send_json(conn, 201, %{meeting_id: meeting_id, status: "connecting"})

        {:error, reason} ->
          send_json(conn, 422, %{error: inspect(reason)})
      end
    else
      send_json(conn, 422, %{error: "meeting_id is required"})
    end
  end

  get "/sessions" do
    sessions =
      ZoomGate.SessionSupervisor.list_sessions()
      |> Enum.map(fn {meeting_id, _pid} -> %{meeting_id: meeting_id} end)

    send_json(conn, 200, %{sessions: sessions})
  end

  get "/sessions/:meeting_id" do
    case ZoomGate.Session.whereis(meeting_id) do
      nil ->
        send_json(conn, 404, %{error: "not_found"})

      _pid ->
        status = ZoomGate.Session.get_status(meeting_id)
        send_json(conn, 200, status)
    end
  end

  delete "/sessions/:meeting_id" do
    case ZoomGate.SessionSupervisor.leave_meeting(meeting_id) do
      :ok -> send_json(conn, 200, %{status: "left"})
      {:error, :not_found} -> send_json(conn, 404, %{error: "not_found"})
    end
  end

  get "/sessions/:meeting_id/participants" do
    with_session(conn, meeting_id, fn ->
      status = ZoomGate.Session.get_status(meeting_id)
      send_json(conn, 200, %{participants: status.participants})
    end)
  end

  get "/sessions/:meeting_id/waiting_room" do
    with_session(conn, meeting_id, fn ->
      status = ZoomGate.Session.get_status(meeting_id)
      send_json(conn, 200, %{waiting_room: status.waiting_room})
    end)
  end

  # -- Session commands --

  post "/sessions/:meeting_id/admit" do
    with_session(conn, meeting_id, fn ->
      zoom_user_id = conn.body_params["zoom_user_id"]
      opts = if dn = conn.body_params["display_name"], do: [display_name: dn], else: []
      ZoomGate.Session.admit(meeting_id, zoom_user_id, opts)
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/deny" do
    with_session(conn, meeting_id, fn ->
      zoom_user_id = conn.body_params["zoom_user_id"]
      opts = if msg = conn.body_params["message"], do: [message: msg], else: []
      ZoomGate.Session.deny(meeting_id, zoom_user_id, opts)
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/rename" do
    with_session(conn, meeting_id, fn ->
      ZoomGate.Session.rename(
        meeting_id,
        conn.body_params["zoom_user_id"],
        conn.body_params["display_name"]
      )

      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/expel" do
    with_session(conn, meeting_id, fn ->
      ZoomGate.Session.expel(meeting_id, conn.body_params["zoom_user_id"])
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/chat" do
    with_session(conn, meeting_id, fn ->
      message = conn.body_params["message"]
      opts = if to = conn.body_params["to"], do: [to: to], else: []
      ZoomGate.Session.send_chat(meeting_id, message, opts)
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/chat_waiting_room" do
    with_session(conn, meeting_id, fn ->
      message = conn.body_params["message"]
      ZoomGate.Session.chat_waiting_room(meeting_id, message)
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/admit_all" do
    with_session(conn, meeting_id, fn ->
      ZoomGate.Session.admit_all(meeting_id)
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/mute" do
    with_session(conn, meeting_id, fn ->
      ZoomGate.Session.mute(meeting_id, conn.body_params["zoom_user_id"])
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/end_meeting" do
    with_session(conn, meeting_id, fn ->
      ZoomGate.Session.end_meeting(meeting_id)
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/start_recording" do
    with_session(conn, meeting_id, fn ->
      ZoomGate.Session.start_recording(meeting_id)
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/stop_recording" do
    with_session(conn, meeting_id, fn ->
      ZoomGate.Session.stop_recording(meeting_id)
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/lock_sharing" do
    with_session(conn, meeting_id, fn ->
      locked = conn.body_params["locked"] == true
      ZoomGate.Session.lock_sharing(meeting_id, locked)
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  post "/sessions/:meeting_id/spotlight" do
    with_session(conn, meeting_id, fn ->
      zoom_user_id = conn.body_params["zoom_user_id"]
      spotlight = Map.get(conn.body_params, "spotlight", true)
      ZoomGate.Session.spotlight(meeting_id, zoom_user_id, spotlight)
      send_json(conn, 200, %{status: "ok"})
    end)
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  # -- Helpers --

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp with_session(conn, meeting_id, fun) do
    case ZoomGate.Session.whereis(meeting_id) do
      nil -> send_json(conn, 404, %{error: "session not found"})
      _pid -> fun.()
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
