defmodule CircuitBreakerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :circuit_breaker

  @session_options [
    store: :cookie,
    key: "_circuit_breaker_key",
    signing_salt: "8fK3mQz1",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :circuit_breaker,
    gzip: false,
    only: ~w(assets)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug CircuitBreakerWeb.Router
end
