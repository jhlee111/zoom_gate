defmodule ZoomGate.Router do
  @moduledoc """
  Top-level router. Delegates `/api` to `ZoomGate.ApiRouter` and serves health checks.
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/health" do
    sessions = ZoomGate.SessionSupervisor.list_sessions()

    send_resp(
      conn,
      200,
      Jason.encode!(%{status: "ok", sessions: length(sessions)})
    )
  end

  forward("/api", to: ZoomGate.ApiRouter)

  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "not_found"}))
  end
end
