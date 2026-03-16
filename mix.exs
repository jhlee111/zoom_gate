defmodule ZoomGate.MixProject do
  use Mix.Project

  def project do
    [
      app: :zoom_gate,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Zoom Meeting SDK bridge — waiting room access control as a service",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ZoomGate.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.6"},
      {:libcluster, "~> 3.4"},
      {:websock_adapter, "~> 0.5"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/anthropics/zoom_gate"}
    ]
  end
end
