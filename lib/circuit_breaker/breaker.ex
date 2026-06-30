defmodule CircuitBreaker.Breaker do
  @moduledoc """
  GenServer implementing a single circuit breaker's state machine.

  States: `:closed` -> `:open` -> `:half_open` -> (`:closed` | `:open`)

  The wrapped function is executed in the *caller's* process, not here —
  this GenServer only arbitrates "can this call proceed right now?" and
  records the outcome. That keeps a slow downstream call from blocking
  every other check against this circuit.
  """

  use GenServer
  require Logger

  alias CircuitBreaker.Config

  defstruct [
    :config,
    state: :closed,
    failure_count: 0,
    success_count: 0,
    last_failure_at: nil,
    last_state_change_at: nil,
    test_in_progress?: false,
    reset_timer_ref: nil
  ]

  @type t :: %__MODULE__{}

  # ── Client API ──────────────────────────────────────────────

  @doc "Starts a breaker process. `name_opt` lets callers control GenServer registration."
  def start_link(%Config{} = config, name_opt \\ []) do
    GenServer.start_link(__MODULE__, config, name_opt)
  end

  @doc """
  Checks whether a call may proceed.

  Returns `:ok` (caller should run their function) or
  `{:error, :circuit_open}` (caller should not run their function).
  """
  def check(server), do: GenServer.call(server, :check)

  @doc "Reports the outcome of a call that was allowed to proceed."
  def report_success(server), do: GenServer.call(server, :report_success)
  def report_failure(server), do: GenServer.call(server, :report_failure)

  @doc "Returns the current state atom: :closed | :open | :half_open"
  def state(server), do: GenServer.call(server, :get_state)

  @doc "Returns a full stats map for dashboards/inspection."
  def stats(server), do: GenServer.call(server, :get_stats)

  @doc "Forces the circuit back to :closed and clears counters."
  def reset(server), do: GenServer.call(server, :force_reset)

  # ── Server callbacks ────────────────────────────────────────

  @impl true
  def init(%Config{} = config) do
    case Config.validate(config) do
      :ok ->
        {:ok, %__MODULE__{config: config, last_state_change_at: DateTime.utc_now()}}

      {:error, reason} ->
        {:stop, {:invalid_config, reason}}
    end
  end

  @impl true
  def handle_call(:check, _from, %__MODULE__{state: :closed} = s) do
    {:reply, :ok, s}
  end

  def handle_call(:check, _from, %__MODULE__{state: :open} = s) do
    {:reply, {:error, :circuit_open}, s}
  end

  def handle_call(:check, _from, %__MODULE__{state: :half_open, test_in_progress?: true} = s) do
    # A test request is already in flight — reject everyone else until it resolves.
    {:reply, {:error, :circuit_open}, s}
  end

  def handle_call(:check, _from, %__MODULE__{state: :half_open, test_in_progress?: false} = s) do
    {:reply, :ok, %{s | test_in_progress?: true}}
  end

  def handle_call(:report_success, _from, %__MODULE__{state: :closed} = s) do
    # Healthy path — reset failure count so isolated blips don't accumulate.
    {:reply, :ok, %{s | failure_count: 0}}
  end

  def handle_call(:report_success, _from, %__MODULE__{state: :half_open} = s) do
    new_success_count = s.success_count + 1

    if new_success_count >= s.config.success_threshold do
      {:reply, :ok, close_circuit(s)}
    else
      {:reply, :ok, %{s | success_count: new_success_count, test_in_progress?: false}}
    end
  end

  def handle_call(:report_failure, _from, %__MODULE__{state: :closed} = s) do
    new_failure_count = s.failure_count + 1
    s = %{s | failure_count: new_failure_count, last_failure_at: DateTime.utc_now()}

    if new_failure_count >= s.config.failure_threshold do
      {:reply, :ok, open_circuit(s)}
    else
      {:reply, :ok, s}
    end
  end

  def handle_call(:report_failure, _from, %__MODULE__{state: :half_open} = s) do
    # Any failure during the trial immediately sends it back to open.
    s = %{s | last_failure_at: DateTime.utc_now()}
    {:reply, :ok, open_circuit(s)}
  end

  def handle_call(:get_state, _from, s), do: {:reply, s.state, s}

  def handle_call(:get_stats, _from, s) do
    stats = %{
      name: s.config.name,
      state: s.state,
      failure_count: s.failure_count,
      success_count: s.success_count,
      last_failure_at: s.last_failure_at,
      last_state_change_at: s.last_state_change_at,
      config: %{
        failure_threshold: s.config.failure_threshold,
        reset_timeout_ms: s.config.reset_timeout_ms,
        success_threshold: s.config.success_threshold
      }
    }

    {:reply, stats, s}
  end

  def handle_call(:force_reset, _from, s) do
    if s.reset_timer_ref, do: Process.cancel_timer(s.reset_timer_ref)

    new_state = %__MODULE__{
      config: s.config,
      state: :closed,
      last_state_change_at: DateTime.utc_now()
    }

    emit_transition(s.config.name, s.state, :closed)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:attempt_reset, %__MODULE__{state: :open} = s) do
    emit_transition(s.config.name, :open, :half_open)

    {:noreply,
     %{
       s
       | state: :half_open,
         success_count: 0,
         test_in_progress?: false,
         reset_timer_ref: nil,
         last_state_change_at: DateTime.utc_now()
     }}
  end

  # Stale timer firing after a manual reset/already-transitioned — ignore.
  def handle_info(:attempt_reset, s), do: {:noreply, s}

  # ── Internal helpers ────────────────────────────────────────

  defp open_circuit(s) do
    if s.reset_timer_ref, do: Process.cancel_timer(s.reset_timer_ref)
    timer_ref = Process.send_after(self(), :attempt_reset, s.config.reset_timeout_ms)

    emit_transition(s.config.name, s.state, :open)

    %{
      s
      | state: :open,
        success_count: 0,
        test_in_progress?: false,
        reset_timer_ref: timer_ref,
        last_state_change_at: DateTime.utc_now()
    }
  end

  defp close_circuit(s) do
    emit_transition(s.config.name, s.state, :closed)

    %{
      s
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        test_in_progress?: false,
        reset_timer_ref: nil,
        last_state_change_at: DateTime.utc_now()
    }
  end

  defp emit_transition(name, from, to) do
    :telemetry.execute(
      [:circuit_breaker, :state_change],
      %{system_time: System.system_time()},
      %{name: name, from: from, to: to}
    )

    Logger.info("[CircuitBreaker] #{inspect(name)}: #{from} -> #{to}")
  end
end
