defmodule ZoomGate.Endpoint do
  @moduledoc """
  Phoenix endpoint for WebSocket and REST API layers.

  - WebSocket: `ws://host:4000/ws/gate` -- real-time bidirectional (Phoenix Channel)
  - REST: `http://host:4000/api/sessions` -- stateless commands + webhook callbacks
  - Dashboard: `http://host:4000/dashboard` -- LiveView monitoring dashboard
  """

  use Phoenix.Endpoint, otp_app: :zoom_gate

  @session_options [
    store: :cookie,
    key: "_zoom_gate_key",
    signing_salt: "zg_dashboard",
    same_site: "Lax"
  ]

  if Code.ensure_loaded?(Tidewave) do
    plug(Tidewave)
  end

  # LiveView WebSocket
  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Channel WebSocket
  socket("/ws", ZoomGate.Socket,
    websocket: [timeout: :infinity],
    longpoll: false
  )

  # Serve Phoenix and LiveView JS from deps static dirs
  plug(Plug.Static,
    at: "/assets/phoenix",
    from: {:phoenix, "priv/static"},
    gzip: false,
    only: ~w(phoenix.min.js)
  )

  plug(Plug.Static,
    at: "/assets/phoenix_live_view",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false,
    only: ~w(phoenix_live_view.min.js)
  )

  # Session plug (required for LiveView CSRF)
  plug(Plug.Session, @session_options)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  # LiveView routes (Phoenix.Router) -- must come before the Plug.Router
  plug(ZoomGate.LiveRouter)

  # API routes (Plug.Router)
  plug(ZoomGate.Router)
end
