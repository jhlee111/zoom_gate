defmodule ZoomGate.Endpoint do
  @moduledoc """
  Phoenix endpoint for WebSocket and REST API layers.

  - WebSocket: `ws://host:4000/ws/gate` — real-time bidirectional (Phoenix Channel)
  - REST: `http://host:4000/api/sessions` — stateless commands + webhook callbacks
  - Dashboard: `http://host:4000/dashboard` — LiveDashboard for monitoring
  """

  use Phoenix.Endpoint, otp_app: :zoom_gate

  if Code.ensure_loaded?(Tidewave) do
    plug(Tidewave)
  end

  socket("/ws", ZoomGate.Socket,
    websocket: [timeout: :infinity],
    longpoll: false
  )

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(ZoomGate.Router)
end
