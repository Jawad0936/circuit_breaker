defmodule CircuitBreaker.Metrics do
  @moduledoc """
  Telemetry integration for circuit breakers.

  Listens for `[:circuit_breaker, :state_change]` events emitted by
  `CircuitBreaker.Breaker` and maintains:

    * an ETS-backed transition log (most recent N transitions, for the
      dashboard's activity feed)
    * per-circuit transition counters (how many times each circuit has
      opened, closed, gone half-open)

  This keeps the dashboard from having to poll every `Breaker` process
  directly — it can read straight from ETS instead.
  """

  use GenServer

  @table __MODULE__
  @max_log_entries 100
  @event [:circuit_breaker, :state_change]
  @handler_id "circuit-breaker-metrics-handler"

  # ── Client API ──────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the most recent transition log entries, newest first."
  @spec recent_transitions(non_neg_integer()) :: [map()]
  def recent_transitions(limit \\ 20) do
    :ets.tab2list(@table)
    |> Enum.filter(fn {key, _} -> key != :counters end)
    |> Enum.map(fn {_key, entry} -> entry end)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc "Returns transition counters per circuit name: %{name => %{opened: n, closed: n, half_opened: n}}"
  @spec counters() :: map()
  def counters do
    case :ets.lookup(@table, :counters) do
      [{:counters, map}] -> map
      [] -> %{}
    end
  end

  # ── Server callbacks ────────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ets.insert(table, {:counters, %{}})

    :telemetry.attach(@handler_id, @event, &__MODULE__.handle_event/4, nil)

    {:ok, %{seq: 0}}
  end

  @doc false
  # Telemetry handlers run in the *caller's* process, not this GenServer's.
  # We write directly to the public ETS table from there instead of
  # round-tripping through a GenServer.call, to keep this off the hot path.
  def handle_event(@event, measurements, %{name: name, from: from, to: to}, _config) do
    at = DateTime.utc_now()
    seq = System.unique_integer([:positive, :monotonic])

    entry = %{
      seq: seq,
      name: name,
      from: from,
      to: to,
      at: at,
      system_time: measurements[:system_time]
    }

    :ets.insert(@table, {{:log, seq}, entry})
    prune_log()
    bump_counter(name, to)
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  # ── Internal helpers ────────────────────────────────────────

  defp bump_counter(name, to_state) do
    counter_key =
      case to_state do
        :open -> :opened
        :closed -> :closed
        :half_open -> :half_opened
      end

    current = counters()
    circuit_counters = Map.get(current, name, %{opened: 0, closed: 0, half_opened: 0})
    updated_circuit_counters = Map.update(circuit_counters, counter_key, 1, &(&1 + 1))
    updated = Map.put(current, name, updated_circuit_counters)
    :ets.insert(@table, {:counters, updated})
  end

  defp prune_log do
    log_keys =
      :ets.tab2list(@table)
      |> Enum.filter(fn {key, _} -> match?({:log, _}, key) end)
      |> Enum.map(fn {key, entry} -> {key, entry.seq} end)

    if length(log_keys) > @max_log_entries do
      log_keys
      |> Enum.sort_by(fn {_key, seq} -> seq end, :desc)
      |> Enum.drop(@max_log_entries)
      |> Enum.each(fn {key, _seq} -> :ets.delete(@table, key) end)
    end
  end
end
