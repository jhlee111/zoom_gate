import Config

config :zoom_gate,
  # C++ worker binary path
  worker_path: System.get_env("ZOOM_GATE_WORKER_PATH", "native/build/zoom_worker"),

  # API authentication
  api_key: System.get_env("ZOOM_GATE_API_KEY")

config :zoom_gate, ZoomGate.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [port: 4000],
  secret_key_base: "dev-only-secret-key-base-that-is-at-least-64-bytes-long-for-development-use",
  server: true,
  pubsub_server: ZoomGate.PubSub

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:meeting_id]

import_config "#{config_env()}.exs"
