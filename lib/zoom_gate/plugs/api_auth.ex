defmodule ZoomGate.Plugs.ApiAuth do
  @moduledoc """
  Plug that validates Bearer token authentication for REST API requests.

  If no `api_key` is configured, all requests are allowed through.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    configured_key = Application.get_env(:zoom_gate, :api_key)

    if is_nil(configured_key) or configured_key == "" do
      conn
    else
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] when token == configured_key ->
          conn

        _ ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
          |> halt()
      end
    end
  end
end
