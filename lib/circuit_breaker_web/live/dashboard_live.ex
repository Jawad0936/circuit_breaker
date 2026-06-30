defmodule CircuitBreakerWeb.DashboardLive do
  use Phoenix.LiveView

  alias CircuitBreaker.{Supervisor, Metrics}

  @refresh_interval_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval_ms, self(), :tick)

    {:ok, assign_data(socket)}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign_data(socket)}
  end

  defp assign_data(socket) do
    circuits =
      Supervisor.list_circuits()
      |> Enum.map(&CircuitBreaker.stats/1)
      |> Enum.sort_by(& &1.name)

    socket
    |> assign(:circuits, circuits)
    |> assign(:transitions, Metrics.recent_transitions(15))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Circuit Breaker Dashboard</h1>
    <p style="color:#8b8f99;">Live view — auto-refreshes every second.</p>

    <table>
      <thead>
        <tr>
          <th>Circuit</th>
          <th>State</th>
          <th>Failures</th>
          <th>Successes</th>
          <th>Last Failure</th>
          <th>Last Change</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={c <- @circuits}>
          <td>{c.name}</td>
          <td><span class={"badge #{c.state}"}>{c.state}</span></td>
          <td>{c.failure_count} / {c.config.failure_threshold}</td>
          <td>{c.success_count} / {c.config.success_threshold}</td>
          <td>{format_time(c.last_failure_at)}</td>
          <td>{format_time(c.last_state_change_at)}</td>
        </tr>
        <tr :if={@circuits == []}>
          <td colspan="6" style="color:#8b8f99;">No circuits running yet.</td>
        </tr>
      </tbody>
    </table>

    <h2 style="margin-top:2rem;">Recent Transitions</h2>
    <div :for={t <- @transitions} class="log-entry">
      <span class={"badge #{t.to}"}>{t.to}</span>
      <strong>{t.name}</strong> transitioned {t.from} → {t.to} at {format_time(t.at)}
    </div>
    """
  end

  defp format_time(nil), do: "—"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
end
