defmodule CircuitBreaker.Registry do
  @moduledoc """
  Thin wrapper around Elixir's `Registry` for naming circuit breaker
  processes by an arbitrary atom (e.g. `:payments_api`) instead of
  needing to track PIDs.
  """

  @registry_name __MODULE__

  @doc "Child spec for the underlying Registry, to be placed in the supervision tree."
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry_name)
  end

  @doc "Returns the `{:via, Registry, ...}` tuple to register/look up a circuit by name."
  def via_tuple(name) do
    {:via, Registry, {@registry_name, name}}
  end

  @doc "Looks up the PID for a given circuit name, if it exists."
  def lookup(name) do
    case Registry.lookup(@registry_name, name) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
