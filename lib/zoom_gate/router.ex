defmodule ZoomGate.Router do
  @moduledoc """
  Top-level router. Delegates `/api` to `ZoomGate.ApiRouter` and serves health checks.
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/health" do
    current = ZoomGate.SessionSupervisor.count_sessions()
    max = Application.get_env(:zoom_gate, :max_sessions, 100)

    send_resp(
      conn,
      200,
      Jason.encode!(%{status: "ok", sessions: current, max_sessions: max})
    )
  end

  forward("/api", to: ZoomGate.ApiRouter)

  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "not_found"}))
  end
end
