defmodule ZoomGate.MixProject do
  use Mix.Project

  def project do
    [
      app: :zoom_gate,
      version: "0.3.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      listeners: [Phoenix.CodeReloader],
      releases: releases(),
      deps: deps(),
      description: "Zoom Meeting SDK bridge — waiting room access control as a service",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets],
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
      {:websock_adapter, "~> 0.5"},

      # Config
      {:dotenvy, "~> 1.1"},

      # WebSocket client for direct RWG connection
      {:gun, "~> 2.1"},
      {:elixir_uuid, "~> 1.2"},

      # Dev tools
      {:tidewave, "~> 0.5", only: :dev}
    ]
  end

  defp releases do
    [
      zoom_gate: [
        include_executables_for: [:unix],
        rel_overlays: ["rel/overlays"]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/anthropics/zoom_gate"}
    ]
  end
end
