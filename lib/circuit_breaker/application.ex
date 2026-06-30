defmodule CircuitBreaker.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CircuitBreaker.Registry,
      CircuitBreaker.Supervisor,
      CircuitBreaker.Metrics,
      {Phoenix.PubSub, name: CircuitBreaker.PubSub},
      CircuitBreakerWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: CircuitBreaker.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
