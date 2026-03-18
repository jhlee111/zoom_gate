defmodule ZoomGate.Analyzer do
  @moduledoc """
  Protocol Analyzer — ICE (In-Circuit Emulator) for Zoom RWG WebSocket protocol.

  Provides a top-level API to enable/disable protocol analysis on meeting sessions.
  When enabled, all WebSocket traffic is recorded, decoded, and tracked in a
  complete client state model. Unknown events are flagged for protocol discovery.

  ## Usage

      # Enable analyzer for a session
      {:ok, pids} = ZoomGate.Analyzer.enable("meeting-123", meeting_number: "999")

      # Query state
      state = ZoomGate.Analyzer.get_state("meeting-123")
      unknowns = ZoomGate.Analyzer.get_unknowns("meeting-123")
      correlations = ZoomGate.Analyzer.get_correlations("meeting-123")

      # Export for offline analysis
      data = ZoomGate.Analyzer.export("meeting-123")

      # Disable
      ZoomGate.Analyzer.disable("meeting-123")
  """

  alias ZoomGate.Analyzer.{StateServer, Tap, Recorder}

  @doc """
  Enable the protocol analyzer for a session.

  Returns `{:ok, %{state_server: pid, tap: pid}}` with the component PIDs.
  If already enabled, returns the existing PIDs.
  """
  @spec enable(String.t(), keyword()) :: {:ok, %{state_server: pid(), tap: pid()}}
  def enable(session_id, opts \\ []) do
    meeting_number = Keyword.get(opts, :meeting_number, "")

    case lookup_state_server(session_id) do
      nil ->
        {:ok, state_server} =
          StateServer.start_link(session_id: session_id, meeting_number: meeting_number)

        {:ok, tap} =
          Tap.start_link(session_id: session_id, state_server: state_server)

        {:ok, %{state_server: state_server, tap: tap}}

      existing_pid ->
        # Already running — find the tap too
        {:ok, %{state_server: existing_pid, tap: existing_pid}}
    end
  end

  @doc "Disable the analyzer and clean up resources."
  @spec disable(String.t()) :: :ok
  def disable(session_id) do
    case lookup_state_server(session_id) do
      nil ->
        :ok

      pid ->
        GenServer.stop(pid, :normal)
        :ok
    end
  end

  @doc "Get current client state."
  @spec get_state(String.t()) :: ZoomGate.Analyzer.ClientState.t() | nil
  def get_state(session_id) do
    with_server(session_id, &StateServer.get_state/1)
  end

  @doc "Get current participants."
  @spec get_participants(String.t()) :: map() | nil
  def get_participants(session_id) do
    with_server(session_id, &StateServer.get_participants/1)
  end

  @doc "Get recorded messages."
  @spec get_records(String.t(), keyword()) :: [map()] | nil
  def get_records(session_id, opts \\ []) do
    with_server(session_id, &StateServer.get_records(&1, opts))
  end

  @doc "Get unknown events discovered during the session."
  @spec get_unknowns(String.t()) :: [map()] | nil
  def get_unknowns(session_id) do
    with_server(session_id, &StateServer.get_unknowns/1)
  end

  @doc "Get command-response correlations."
  @spec get_correlations(String.t()) :: [map()] | nil
  def get_correlations(session_id) do
    with_server(session_id, &StateServer.get_correlations/1)
  end

  @doc "Export all recorded data for offline analysis."
  @spec export(String.t()) :: [map()] | nil
  def export(session_id) do
    case lookup_state_server(session_id) do
      nil -> nil
      _pid -> Recorder.export(session_id)
    end
  end

  @doc "Subscribe to state change notifications."
  @spec subscribe(String.t()) :: :ok | nil
  def subscribe(session_id) do
    with_server(session_id, &StateServer.subscribe/1)
  end

  # -- Private --

  defp lookup_state_server(session_id) do
    case Registry.lookup(ZoomGate.Registry, {:analyzer, session_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp with_server(session_id, fun) do
    case lookup_state_server(session_id) do
      nil -> nil
      pid -> fun.(pid)
    end
  end
end
