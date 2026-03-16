defmodule ZoomGate.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # PubSub for Phoenix Channels
      {Phoenix.PubSub, name: ZoomGate.PubSub},

      # Process registry for meeting sessions
      {Registry, keys: :unique, name: ZoomGate.Registry},

      # Dynamic supervisor for per-meeting bot sessions
      {ZoomGate.SessionSupervisor, []},

      # Phoenix endpoint (WebSocket + REST API)
      {ZoomGate.Endpoint, []},

      # Cluster formation (connects to BEAM peers like GsNet)
      cluster_supervisor()
    ]

    opts = [strategy: :one_for_one, name: ZoomGate.Supervisor]
    Supervisor.start_link(Enum.reject(children, &is_nil/1), opts)
  end

  defp cluster_supervisor do
    topologies = Application.get_env(:zoom_gate, :cluster_topologies, [])

    if topologies != [] do
      {Cluster.Supervisor, [topologies, [name: ZoomGate.ClusterSupervisor]]}
    end
  end
end
