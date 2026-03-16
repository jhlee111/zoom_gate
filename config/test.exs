import Config

config :zoom_gate,
  worker_path: Path.expand("../test/support/mock_worker.py", __DIR__),
  worker_command: "python3",
  api_key: "test-api-key"

config :zoom_gate, ZoomGate.Endpoint,
  http: [port: 4002],
  server: false

config :logger, level: :warning
