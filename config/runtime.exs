import Config

# Runtime configuration — read from environment variables at boot.
# Unlike config/prod.exs, this file is evaluated every time the release starts,
# not at compile time.

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :zoom_gate, ZoomGate.Endpoint,
    url: [host: System.get_env("PHX_HOST", "localhost")],
    http: [port: String.to_integer(System.get_env("PORT", "4000"))],
    secret_key_base: secret_key_base,
    server: true

  config :zoom_gate,
    worker_path: System.get_env("ZOOM_GATE_WORKER_PATH", "/app/bin/zoom_worker"),
    api_key: System.get_env("ZOOM_GATE_API_KEY")

  # libcluster for BEAM cluster (connects to GsNet, etc.)
  cluster_hosts =
    case System.get_env("CLUSTER_HOSTS") do
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
