defmodule CircuitBreaker.MixProject do
  use Mix.Project

  def project do
    [
      app: :circuit_breaker,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CircuitBreaker.Application, []}
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:stream_data, "~> 0.6", only: :test}
    ]
  end
end
