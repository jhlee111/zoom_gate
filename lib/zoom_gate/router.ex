defmodule ZoomGate.Router do
  @moduledoc """
  REST API router for ZoomGate.

  ## Endpoints

      POST   /api/sessions                       Create bot session (join meeting)
      GET    /api/sessions                       List active sessions
      GET    /api/sessions/:meeting_id           Get session status
      DELETE /api/sessions/:meeting_id           Stop session (leave meeting)
      POST   /api/sessions/:meeting_id/admit     Admit from waiting room
      POST   /api/sessions/:meeting_id/deny      Deny and remove from waiting room
      POST   /api/sessions/:meeting_id/rename    Rename participant
      POST   /api/sessions/:meeting_id/expel     Remove from meeting
      POST   /api/sessions/:meeting_id/chat      Send chat message
      GET    /health                             Health check
  """

  use Plug.Router

  plug :match
  plug :dispatch

  get "/health" do
    send_resp(conn, 200, Jason.encode!(%{status: "ok", sessions: length(ZoomGate.SessionSupervisor.list_sessions())}))
  end

  # TODO: REST API implementation (P4-2)
  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "not_found"}))
  end
end
