import Config

config :zoom_gate,
  bot_module: ZoomGate.MockMeetingBot,
  api_key: "test-api-key",
  max_sessions: 1000

config :zoom_gate, ZoomGate.Endpoint,
  http: [port: 4002],
  server: false

config :logger, level: :warning
