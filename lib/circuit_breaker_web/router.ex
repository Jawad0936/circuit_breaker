defmodule CircuitBreakerWeb.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_root_layout, html: {CircuitBreakerWeb.Layouts, :root}
  end

  scope "/", CircuitBreakerWeb do
    pipe_through :browser

    live "/", DashboardLive
  end
end
