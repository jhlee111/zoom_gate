defmodule Mix.Tasks.GenJwt do
  @moduledoc "Generates a JWT token for Zoom SDK auth. Usage: mix gen_jwt"
  use Mix.Task

  @shortdoc "Generate Zoom SDK JWT token from .env credentials"

  @impl true
  def run(_args) do
    load_env_file()

    sdk_key = System.get_env("ZOOM_SDK_KEY", "")
    sdk_secret = System.get_env("ZOOM_SDK_SECRET", "")

    if sdk_key == "" or sdk_secret == "" do
      Mix.shell().error("ZOOM_SDK_KEY and ZOOM_SDK_SECRET must be set in .env")
    else
      token = ZoomGate.SdkJwt.generate(sdk_key, sdk_secret)
      Mix.shell().info(token)
    end
  end

  defp load_env_file do
    env_path = Path.expand(".env", File.cwd!())

    if File.exists?(env_path) do
      env_path
      |> File.read!()
      |> String.split("\n")
      |> Enum.each(&parse_env_line/1)
    end
  end

  defp parse_env_line(line) do
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = String.trim(value)
        if key != "" and not String.starts_with?(key, "#"), do: System.put_env(key, value)

      _ ->
        :ok
    end
  end
end
