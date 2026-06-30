defmodule CircuitBreaker.Config do
  @moduledoc """
  Configuration for a single circuit breaker instance.

  Holds the tunable thresholds that govern state transitions:

    * `:failure_threshold`  — consecutive failures (in `:closed`) before opening
    * `:reset_timeout_ms`   — time to wait in `:open` before trying `:half_open`
    * `:success_threshold`  — consecutive successes (in `:half_open`) before closing
  """

  @enforce_keys [:name]
  defstruct name: nil,
            failure_threshold: 5,
            reset_timeout_ms: 30_000,
            success_threshold: 2

  @type t :: %__MODULE__{
          name: atom(),
          failure_threshold: pos_integer(),
          reset_timeout_ms: non_neg_integer(),
          success_threshold: pos_integer()
        }

  @doc """
  Builds a `Config` struct from a circuit name and keyword opts.

  ## Examples

      iex> CircuitBreaker.Config.new(:payments_api, failure_threshold: 3)
      %CircuitBreaker.Config{name: :payments_api, failure_threshold: 3, reset_timeout_ms: 30_000, success_threshold: 2}
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) and is_list(opts) do
    struct!(__MODULE__, [name: name] ++ opts)
  end

  @doc """
  Validates that all thresholds are sane positive values.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = config) do
    cond do
      not is_integer(config.failure_threshold) or config.failure_threshold < 1 ->
        {:error, "failure_threshold must be a positive integer"}

      not is_integer(config.reset_timeout_ms) or config.reset_timeout_ms < 0 ->
        {:error, "reset_timeout_ms must be a non-negative integer"}

      not is_integer(config.success_threshold) or config.success_threshold < 1 ->
        {:error, "success_threshold must be a positive integer"}

      true ->
        :ok
    end
  end
end
