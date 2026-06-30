import Config

config :circuit_breaker, CircuitBreakerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: true,
  secret_key_base: "HUEpJPw/WYvU3JRHjaToOO2Bd9+Wad2mrbAR7STxeNsAJYiaBA/zXQOGL55gtwkVCuvq4EGi2Sovmy77WvAQEEpgz6ZQahZxKgEzSH3Cqka5iBnx/atuE7dx7husgXt",
  live_view: [signing_salt: "kx7Hq2vL"],
  pubsub_server: CircuitBreaker.PubSub,
  render_errors: [formats: [html: CircuitBreakerWeb.ErrorHTML], layout: false],
  check_origin: false

config :phoenix, :json_library, Jason

config :logger, :console, format: "$time $metadata[$level] $message\n"
