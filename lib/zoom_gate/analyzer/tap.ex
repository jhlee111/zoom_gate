defmodule ZoomGate.Analyzer.Tap do
  @moduledoc """
  Lightweight GenServer that taps into MeetingBot's WebSocket traffic.

  Receives raw `{:raw_ws, direction, data}` messages from MeetingBot,
  decodes them via EventDecoder, and forwards to StateServer for
  state tracking and recording.
  """

  use GenServer

  alias ZoomGate.Analyzer.StateServer
  alias ZoomGate.MeetingBot.Frame

  defstruct [:session_id, :state_server]

  @doc "Start the tap process."
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    state_server = Keyword.fetch!(opts, :state_server)
    GenServer.start_link(__MODULE__, {session_id, state_server})
  end

  @impl true
  def init({session_id, state_server}) do
    Process.monitor(state_server)
    {:ok, %__MODULE__{session_id: session_id, state_server: state_server}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{state_server: pid} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:raw_ws, direction, {:binary, data}}, state) do
    handle_binary_frame(direction, data, state)
    {:noreply, state}
  end

  def handle_info({:raw_ws, direction, data}, state) when is_binary(data) do
    handle_text_frame(direction, data, state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -- Private --

  defp handle_text_frame(direction, json, state) do
    case Jason.decode(json) do
      {:ok, event} ->
        StateServer.inject_event(state.state_server, direction, event, json)

      {:error, _} ->
        :ok
    end
  end

  defp handle_binary_frame(direction, data, state) do
    case Frame.decode(data) do
      {:data, json, _wire_seq} ->
        handle_text_frame(direction, json, state)

      {:ping, _} ->
        :ok

      {:pong, _} ->
        :ok

      _ ->
        :ok
    end
  end
end
