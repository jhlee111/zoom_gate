import Config

config :zoom_gate, ZoomGate.Endpoint,
  http: [port: 4002],
  server: false

config :logger, level: :warning
