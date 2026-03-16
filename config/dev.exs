import Config

config :zoom_gate, ZoomGate.Endpoint,
  http: [port: 4100],
  debug_errors: true,
  check_origin: false

config :logger, level: :debug
