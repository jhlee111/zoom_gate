defmodule ZoomGate.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # PubSub for Phoenix Channels + distributed event delivery
        {Phoenix.PubSub, name: ZoomGate.PubSub},

        # Process registry for meeting sessions
        {Registry, keys: :unique, name: ZoomGate.Registry},

        # Dynamic supervisor for per-meeting bot sessions
        # shutdown: 15s to allow bots to leave meetings gracefully
        {ZoomGate.SessionSupervisor, []},

        # Phoenix endpoint (WebSocket + REST API)
        # Skipped when start_endpoint: false (embedded library mode)
        endpoint_child(),

        # Cluster formation (connects to BEAM peers like GsNet)
        cluster_supervisor()
      ]
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: ZoomGate.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp endpoint_child do
    if Application.get_env(:zoom_gate, :start_endpoint, true) do
      {ZoomGate.Endpoint, []}
    end
  end

  defp cluster_supervisor do
    topologies = Application.get_env(:zoom_gate, :cluster_topologies, [])

    if topologies != [] do
      {Cluster.Supervisor, [topologies, [name: ZoomGate.ClusterSupervisor]]}
    end
  end
end
