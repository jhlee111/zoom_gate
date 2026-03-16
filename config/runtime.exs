import Config
import Dotenvy

# Runtime configuration — read from .env files and environment variables at boot.
# File precedence: .env → {env}.env → system env vars (highest priority)

source!([
  Path.expand("../.env", __DIR__),
  Path.expand("../#{config_env()}.env", __DIR__),
  System.get_env()
])

if config_env() == :prod do
  secret_key_base =
    env!("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :zoom_gate, ZoomGate.Endpoint,
    url: [host: env!("PHX_HOST", :string, "localhost")],
    http: [port: env!("PORT", :integer, 4000)],
    secret_key_base: secret_key_base,
    server: true

  config :zoom_gate,
    worker_path: env!("ZOOM_GATE_WORKER_PATH", :string, "/app/bin/zoom_worker"),
    api_key: env!("ZOOM_GATE_API_KEY", :string, nil)

  # libcluster for BEAM cluster (connects to GsNet, etc.)
  cluster_hosts =
    case env!("CLUSTER_HOSTS", :string, nil) do
      nil -> []
      "" -> []
      hosts -> hosts |> String.split(",") |> Enum.map(&String.to_atom/1)
    end

  if cluster_hosts != [] do
    config :zoom_gate,
      cluster_topologies: [
        zoom_gate: [
          strategy: Cluster.Strategy.Epmd,
          config: [hosts: cluster_hosts]
        ]
      ]
  end
end

# Dev/test: load SDK credentials from .env
if config_env() in [:dev, :test] do
  config :zoom_gate,
    zoom_sdk_key: env!("ZOOM_SDK_KEY", :string, nil),
    zoom_sdk_secret: env!("ZOOM_SDK_SECRET", :string, nil)
end
