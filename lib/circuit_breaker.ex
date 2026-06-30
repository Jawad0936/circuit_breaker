defmodule CircuitBreaker do
  @moduledoc """
  Public API for the Circuit Breaker library.

  ## Example

      CircuitBreaker.start(:payments_api,
        failure_threshold: 5,
        reset_timeout_ms: 30_000,
        success_threshold: 2
      )

      CircuitBreaker.call(:payments_api, fn ->
        PaymentsAPI.charge(user_id, amount)
      end)

      CircuitBreaker.call(:payments_api,
        fn -> PaymentsAPI.charge(user_id, amount) end,
        fallback: fn -> {:ok, :queued_for_retry} end
      )
  """

  alias CircuitBreaker.{Config, Supervisor, Breaker, Registry}

  @doc """
  Starts a new named circuit breaker.

  Returns `{:ok, pid}` on success, `{:error, {:already_started, pid}}` if
  a circuit with that name is already running, or `{:error, reason}` if
  the config is invalid.
  """
  @spec start(atom(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start(name, opts \\ []) when is_atom(name) do
    name
    |> Config.new(opts)
    |> Supervisor.start_circuit()
  end

  @doc """
  Wraps a call to a downstream service through the named circuit breaker.

  If the circuit is closed (or half-open and this is the test request),
  `fun` is executed in the caller's process and the outcome is reported
  back to the breaker. If the circuit is open, `fun` is never called.

  Returns:
    * `{:ok, result}` — the wrapped function ran and returned `{:ok, result}`
    * `{:error, reason}` — the wrapped function ran and returned `{:error, reason}`
    * `{:error, :circuit_open}` — the circuit was open; `fun` did not run
    * whatever `fallback` returns/produces, if provided and the circuit was open

  ## Options
    * `:fallback` — a value, or zero-arity function, returned/called when
      the circuit is open instead of `{:error, :circuit_open}`
  """
  @spec call(atom(), (-> term()), keyword()) :: term()
  def call(name, fun, opts \\ []) when is_function(fun, 0) do
    via = Registry.via_tuple(name)

    case Breaker.check(via) do
      :ok ->
        run_and_report(via, fun)

      {:error, :circuit_open} ->
        handle_open(opts)
    end
  end

  @doc "Returns the current state of a circuit: `:closed | :open | :half_open`."
  @spec state(atom()) :: :closed | :open | :half_open
  def state(name) do
    name
    |> Registry.via_tuple()
    |> Breaker.state()
  end

  @doc "Returns a stats map for the named circuit."
  @spec stats(atom()) :: map()
  def stats(name) do
    name
    |> Registry.via_tuple()
    |> Breaker.stats()
  end

  @doc "Forces the named circuit back to `:closed`, clearing counters."
  @spec reset(atom()) :: :ok
  def reset(name) do
    name
    |> Registry.via_tuple()
    |> Breaker.reset()
  end

  @doc "Stops and removes the named circuit entirely."
  @spec stop(atom()) :: :ok | {:error, :not_found}
  def stop(name), do: Supervisor.stop_circuit(name)

  @doc "Lists the names of all currently running circuits."
  @spec list() :: [atom()]
  def list, do: Supervisor.list_circuits()

  # ── Internal helpers ────────────────────────────────────────

  defp run_and_report(via, fun) do
    try do
      case fun.() do
        {:ok, _} = ok ->
          Breaker.report_success(via)
          ok

        {:error, _} = error ->
          Breaker.report_failure(via)
          error

        other ->
          # Any non-{:ok, _}/{:error, _} return is treated as success —
          # the breaker only cares about explicit failure signaling.
          Breaker.report_success(via)
          other
      end
    rescue
      exception ->
        Breaker.report_failure(via)
        {:error, {:exception, exception}}
    end
  end

  defp handle_open(opts) do
    case Keyword.get(opts, :fallback) do
      nil -> {:error, :circuit_open}
      fallback when is_function(fallback, 0) -> fallback.()
      fallback -> fallback
    end
  end
end
