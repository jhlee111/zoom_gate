defmodule Mix.Tasks.Openapi do
  @shortdoc "Generates OpenAPI 3.0 JSON spec to priv/static/openapi.json"
  @moduledoc """
  Generates the OpenAPI 3.0 specification for ZoomGate's REST API.

  The JSON file is written to `priv/static/openapi.json`.

  ## Usage

      mix openapi
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    spec = ZoomGate.ApiSpec.spec() |> Jason.encode!(pretty: true)
    File.mkdir_p!("priv/static")
    File.write!("priv/static/openapi.json", spec)
    Mix.shell().info("Generated priv/static/openapi.json")
  end
end
