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
      package: package(),
      docs: docs()
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
      {:tidewave, "~> 0.5", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # Documentation
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:open_api_spex, "~> 3.21"}
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

  defp docs do
    [
      main: "ZoomGate",
      source_url: "https://github.com/jhlee111/zoom_gate",
      extras: [
        "README.md",
        "guides/session-lifecycle.md",
        "guides/authentication.md",
        "guides/webhooks.md",
        "guides/webhook-rwg-integration.md",
        "guides/error-reference.md",
        "guides/library-integration.md",
        "guides/gsnet-integration.md",
        "guides/protocol-analyzer.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          ZoomGate,
          ZoomGate.Session,
          ZoomGate.SessionSupervisor
        ],
        "API Layer": [
          ZoomGate.Endpoint,
          ZoomGate.Socket,
          ZoomGate.GateChannel,
          ZoomGate.ApiRouter,
          ZoomGate.SessionController,
          ZoomGate.ApiSpec
        ],
        "Meeting Bot": [
          ZoomGate.MeetingBot,
          ZoomGate.MeetingBot.Protocol,
          ZoomGate.MeetingBot.Frame,
          ZoomGate.MeetingBot.Participant
        ],
        "Protocol Analyzer": [
          ZoomGate.Analyzer,
          ZoomGate.Analyzer.ClientState,
          ZoomGate.Analyzer.EnrichedParticipant,
          ZoomGate.Analyzer.MeetingSettings,
          ZoomGate.Analyzer.ChatMessage,
          ZoomGate.Analyzer.EventRegistry,
          ZoomGate.Analyzer.EventRegistry.EventInfo,
          ZoomGate.Analyzer.EventDecoder,
          ZoomGate.Analyzer.Recorder,
          ZoomGate.Analyzer.Correlator,
          ZoomGate.Analyzer.StateServer,
          ZoomGate.Analyzer.Tap
        ]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/jhlee111/zoom_gate"},
      files: ~w(lib config mix.exs README.md LICENSE usage-rules.md)
    ]
  end
end
