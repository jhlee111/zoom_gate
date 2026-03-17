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
    api_key: env!("ZOOM_GATE_API_KEY", :string, nil),
    max_sessions: env!("ZOOM_GATE_MAX_SESSIONS", :integer, 100)

  # Logging
  log_level =
    case env!("ZOOM_GATE_LOG_LEVEL", :string, "info") do
      "debug" -> :debug
      "info" -> :info
      "warning" -> :warning
      "error" -> :error
      _ -> :info
    end

  config :logger, level: log_level

  # -- Cluster strategy --
  cluster_strategy = env!("CLUSTER_STRATEGY", :string, "epmd")

  cluster_topologies =
    case cluster_strategy do
      "epmd" ->
        case env!("CLUSTER_HOSTS", :string, nil) do
          nil ->
            []

          "" ->
            []

          hosts ->
            [
              zoom_gate: [
                strategy: Cluster.Strategy.Epmd,
                config: [hosts: hosts |> String.split(",") |> Enum.map(&String.to_atom/1)]
              ]
            ]
        end

      "dns" ->
        service = env!("CLUSTER_DNS_SERVICE", :string, "zoom-gate-headless")
        app_name = env!("CLUSTER_DNS_APP_NAME", :string, "zoom_gate")

        [
          zoom_gate: [
            strategy: Cluster.Strategy.Kubernetes.DNS,
            config: [service: service, application_name: app_name]
          ]
        ]

      "gossip" ->
        [
          zoom_gate: [
            strategy: Cluster.Strategy.Gossip,
            config: [port: env!("CLUSTER_GOSSIP_PORT", :integer, 45892)]
          ]
        ]

      _ ->
        []
    end

  if cluster_topologies != [] do
    config :zoom_gate, cluster_topologies: cluster_topologies
  end
end

# Dev/test: load SDK credentials from .env (convenience only)
if config_env() in [:dev, :test] do
  config :zoom_gate,
    zoom_sdk_key: env!("ZOOM_SDK_KEY", :string, nil),
    zoom_sdk_secret: env!("ZOOM_SDK_SECRET", :string, nil)
end
