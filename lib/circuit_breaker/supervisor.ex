defmodule CircuitBreaker.Supervisor do
  @moduledoc """
  DynamicSupervisor responsible for starting and supervising individual
  `CircuitBreaker.Breaker` processes on demand.
  """

  use DynamicSupervisor

  alias CircuitBreaker.{Breaker, Config, Registry}

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new circuit breaker under supervision, registered by name.

  Returns `{:ok, pid}`, `{:error, {:already_started, pid}}` if a circuit
  with that name already exists, or `{:error, reason}` on invalid config.
  """
  def start_circuit(%Config{} = config) do
    child_spec = %{
      id: Breaker,
      start: {Breaker, :start_link, [config, [name: Registry.via_tuple(config.name)]]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc "Stops and removes a circuit breaker by name."
  def stop_circuit(name) do
    case Registry.lookup(name) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc "Lists all currently running circuit names."
  def list_circuits do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.map(&Breaker.stats/1)
    |> Enum.map(& &1.name)
  end
end
