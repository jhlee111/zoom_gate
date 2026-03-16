import Config

config :zoom_gate, ZoomGate.Endpoint,
  url: [host: System.get_env("PHX_HOST", "localhost")],
  http: [port: String.to_integer(System.get_env("PORT", "4000"))],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  server: true

config :zoom_gate,
  worker_path: "/app/bin/zoom_worker",
  api_key: System.get_env("ZOOM_GATE_API_KEY")

# libcluster for BEAM cluster
cluster_hosts =
  case System.get_env("CLUSTER_HOSTS") do
    nil -> []
    hosts -> hosts |> String.split(",") |> Enum.map(&String.to_atom/1)
  end

if cluster_hosts != [] do
  config :libcluster,
    topologies: [
      zoom_gate: [
        strategy: Cluster.Strategy.Epmd,
        config: [hosts: cluster_hosts]
      ]
    ]
end

config :logger, level: :info
