defmodule ZoomGate.LiveRouter do
  @moduledoc """
  Phoenix Router for LiveView pages.

  The main ZoomGate router is a `Plug.Router` (for REST API + webhooks),
  but LiveView requires a `Phoenix.Router` with session and CSRF support.
  This router handles the `/dashboard` route and falls through for everything else.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:put_root_layout, html: {ZoomGate.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", ZoomGate do
    pipe_through(:browser)

    live("/dashboard", DashboardLive)
  end
end
