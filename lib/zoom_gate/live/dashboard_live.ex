defmodule ZoomGate.DashboardLive do
  @moduledoc """
  Real-time monitoring dashboard for ZoomGate sessions.

  Shows active sessions, participant counts, bot health, and webhook events,
  all updating in real-time via PubSub and periodic polling.

  Accessible at `/dashboard`.
  """

  use Phoenix.LiveView

  @max_events 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom:webhooks")
      # Subscribe to session lifecycle (new sessions starting/stopping)
      Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom_gate:sessions")
    end

    sessions = fetch_sessions()
    subscribe_to_sessions(sessions)

    {:ok,
     assign(socket,
       sessions: sessions,
       session_count: length(sessions),
       subscribed_meetings: Enum.map(sessions, & &1.meeting_id) |> MapSet.new(),
       events: [],
       expanded_session: nil
     )}
  end

  # Session PubSub events — refresh on any change
  @impl true
  def handle_info({:zoom_gate, _event}, socket) do
    sessions = fetch_sessions()

    # Subscribe to any new sessions
    new_ids = Enum.map(sessions, & &1.meeting_id) |> MapSet.new()
    old_ids = socket.assigns.subscribed_meetings

    for mid <- MapSet.difference(new_ids, old_ids) do
      Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom_gate:#{mid}")
    end

    {:noreply, assign(socket, sessions: sessions, session_count: length(sessions), subscribed_meetings: new_ids)}
  end

  @impl true
  def handle_info({:zoom_webhook, event_type, data}, socket) do
    event = %{
      id: System.unique_integer([:positive]),
      timestamp: DateTime.utc_now(),
      event_type: event_type,
      meeting_id: extract_meeting_id(data),
      user_name: data[:user_name],
      email: data[:email],
      data: data
    }

    events =
      [event | socket.assigns.events]
      |> Enum.take(@max_events)

    {:noreply, assign(socket, events: events)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("end_meeting", %{"meeting_id" => meeting_id}, socket) do
    case ZoomGate.Session.whereis(meeting_id) do
      nil -> :ok
      _pid -> ZoomGate.Session.end_meeting(meeting_id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_session", %{"meeting_id" => meeting_id}, socket) do
    expanded =
      if socket.assigns.expanded_session == meeting_id,
        do: nil,
        else: meeting_id

    {:noreply, assign(socket, expanded_session: expanded)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <header class="header">
        <h1>ZoomGate Dashboard</h1>
        <div class="header-stats">
          <div class="stat-badge">
            <span>Active Sessions</span>
            <span class="value">{@session_count}</span>
          </div>
          <div class="stat-badge">
            <div class="pulse-dot"></div>
            <span>Live</span>
          </div>
        </div>
      </header>

      <div class="grid">
        <%!-- Sessions Table --%>
        <div class="card sessions-section">
          <div class="card-title">
            Sessions
            <span class="count">{@session_count}</span>
          </div>

          <%= if @sessions == [] do %>
            <div class="empty-state">
              No active sessions. Start a meeting bot to see it here.
            </div>
          <% else %>
            <table class="sessions-table">
              <thead>
                <tr>
                  <th>Meeting ID</th>
                  <th>Status</th>
                  <th>Bot Health</th>
                  <th>Restarts</th>
                  <th>Participants</th>
                  <th>Waiting Room</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for session <- @sessions do %>
                  <tr
                    style="cursor: pointer;"
                    phx-click="toggle_session"
                    phx-value-meeting_id={session.meeting_id}
                  >
                    <td>
                      <span class="meeting-id">{session.meeting_id}</span>
                    </td>
                    <td>
                      <span class={"status status-#{session.status}"}>{session.status}</span>
                    </td>
                    <td>
                      <.bot_health health={session.bot_health} />
                    </td>
                    <td>
                      <%= if session.bot_restart_attempts > 0 do %>
                        <span class="restart-badge">{session.bot_restart_attempts}/3</span>
                      <% else %>
                        <span style="color: #666680;">0</span>
                      <% end %>
                    </td>
                    <td>
                      <span class="count-badge count-participants">
                        {map_size(session.participants)}
                      </span>
                    </td>
                    <td>
                      <span class="count-badge count-waiting">
                        {map_size(session.waiting_room)}
                      </span>
                    </td>
                    <td>
                      <button
                        class="btn btn-danger"
                        phx-click="end_meeting"
                        phx-value-meeting_id={session.meeting_id}
                        data-confirm="End this meeting?"
                      >
                        End
                      </button>
                    </td>
                  </tr>
                  <%= if @expanded_session == session.meeting_id do %>
                    <tr>
                      <td colspan="7" style="padding: 0 12px 12px;">
                        <.session_detail session={session} />
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>

        <%!-- Webhook Events Feed --%>
        <div class="card">
          <div class="card-title">
            Webhook Events
            <span class="count">{length(@events)}</span>
          </div>

          <%= if @events == [] do %>
            <div class="empty-state">
              No webhook events yet. Events will appear as Zoom sends them.
            </div>
          <% else %>
            <div class="events-feed" id="events-feed">
              <%= for event <- @events do %>
                <div class="event-item" id={"event-#{event.id}"}>
                  <span class="event-time">{format_time(event.timestamp)}</span>
                  <span class={"event-type event-type-#{event_type_class(event.event_type)}"}>{format_event_type(event.event_type)}</span>
                  <div class="event-detail">
                    <%= if event.user_name do %>
                      <span>{event.user_name}</span>
                    <% end %>
                    <%= if event.email do %>
                      <span style="color: #666680; font-size: 11px;"> ({event.email})</span>
                    <% end %>
                    <%= if event.meeting_id && event.meeting_id != "" do %>
                      <span class="event-meeting"> #{event.meeting_id}</span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # -- Components --

  defp bot_health(assigns) do
    ~H"""
    <div class="health">
      <%= case health_level(@health) do %>
        <% :green -> %>
          <div class="health-dot health-green"></div>
          <span class="health-text">{health_label(@health)}</span>
        <% :yellow -> %>
          <div class="health-dot health-yellow"></div>
          <span class="health-text">{health_label(@health)}</span>
        <% :red -> %>
          <div class="health-dot health-red"></div>
          <span class="health-text">{health_label(@health)}</span>
      <% end %>
    </div>
    """
  end

  defp session_detail(assigns) do
    ~H"""
    <div class="participant-detail">
      <div style="margin-bottom: 12px;">
        <div class="section-label">Participants ({map_size(@session.participants)})</div>
        <%= if map_size(@session.participants) == 0 do %>
          <span style="color: #666680; font-size: 12px;">None</span>
        <% else %>
          <div class="participant-list">
            <%= for {_uid, p} <- @session.participants do %>
              <span class="participant-chip">{participant_name(p)}</span>
            <% end %>
          </div>
        <% end %>
      </div>
      <div>
        <div class="section-label">Waiting Room ({map_size(@session.waiting_room)})</div>
        <%= if map_size(@session.waiting_room) == 0 do %>
          <span style="color: #666680; font-size: 12px;">Empty</span>
        <% else %>
          <div class="participant-list">
            <%= for {_uid, p} <- @session.waiting_room do %>
              <span class="participant-chip waiting">{participant_name(p)}</span>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # -- Helpers --

  defp fetch_sessions do
    ZoomGate.SessionSupervisor.list_sessions()
    |> Enum.map(fn {meeting_id, _pid} ->
      try do
        status = ZoomGate.Session.get_status(meeting_id)
        if is_map(status) && Map.has_key?(status, :meeting_id), do: status
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp subscribe_to_sessions(sessions) do
    for session <- sessions do
      Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom_gate:#{session.meeting_id}")
    end
  end

  defp extract_meeting_id(%{meeting_id: id}) when is_binary(id), do: id
  defp extract_meeting_id(_), do: nil

  defp health_level(%{status: :active, heartbeat_age_ms: age}) when is_integer(age) and age < 30_000, do: :green
  defp health_level(%{status: :active, heartbeat_age_ms: age}) when is_integer(age) and age < 90_000, do: :yellow
  defp health_level(%{status: :active}), do: :green
  defp health_level(%{status: :connecting}), do: :yellow
  defp health_level(%{status: :reconnecting}), do: :yellow
  defp health_level(%{status: :not_running}), do: :red
  defp health_level(%{status: :unreachable}), do: :red
  defp health_level(_), do: :red

  defp health_label(%{status: :active, heartbeat_age_ms: age}) when is_integer(age) do
    cond do
      age < 1_000 -> "<1s"
      age < 60_000 -> "#{div(age, 1_000)}s"
      true -> "#{div(age, 60_000)}m"
    end
  end

  defp health_label(%{status: :active}), do: "ok"
  defp health_label(%{status: :not_running}), do: "down"
  defp health_label(%{status: :connecting}), do: "connecting"
  defp health_label(%{status: :reconnecting}), do: "reconnecting"
  defp health_label(%{status: :unreachable}), do: "unreachable"
  defp health_label(%{status: status}), do: to_string(status)
  defp health_label(_), do: "unknown"

  defp participant_name(%{display_name: name} = p) when is_binary(name) and name != "" do
    role_tag = cond do
      Map.get(p, :is_host, false) -> " [Host]"
      Map.get(p, :role) == 1 -> " [Host]"
      Map.get(p, :is_cohost, false) -> " [CoHost]"
      Map.get(p, :role) == 2 -> " [CoHost]"
      true -> ""
    end
    name <> role_tag
  end
  defp participant_name(%{zoom_user_id: uid}), do: "User #{uid}"
  defp participant_name(_), do: "Unknown"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_event_type(:participant_waiting), do: "waiting"
  defp format_event_type(:participant_admitted), do: "admitted"
  defp format_event_type(:participant_joined), do: "joined"
  defp format_event_type(:participant_left), do: "left"
  defp format_event_type(:raw), do: "raw"
  defp format_event_type(other), do: to_string(other)

  defp event_type_class(:participant_waiting), do: "waiting"
  defp event_type_class(:participant_admitted), do: "admitted"
  defp event_type_class(:participant_joined), do: "joined"
  defp event_type_class(:participant_left), do: "left"
  defp event_type_class(_), do: "raw"
end
