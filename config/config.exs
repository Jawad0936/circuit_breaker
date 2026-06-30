import Config

config :circuit_breaker, CircuitBreakerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: true,
  secret_key_base: "Y3VuVAdQrLm9aBxKqW2nE5pT8sJ4hF7gD1cV6zX0oI3uR9yM2kL5wQ8eN1bS4j",
  live_view: [signing_salt: "kx7Hq2vL"],
  pubsub_server: CircuitBreaker.PubSub,
  render_errors: [formats: [html: CircuitBreakerWeb.ErrorHTML], layout: false],
  check_origin: false

config :phoenix, :json_library, Jason

config :logger, :console, format: "$time $metadata[$level] $message\n"
