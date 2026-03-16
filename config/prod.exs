import Config

# Compile-time production config.
# Runtime env vars are in config/runtime.exs.

config :zoom_gate, ZoomGate.Endpoint, server: true

config :logger, level: :info
