defmodule ZoomGate.Socket do
  @moduledoc """
  Phoenix Socket for WebSocket consumers (Node.js, Python, browsers, etc.).

  Clients connect to `ws://host:4000/ws/gate` and join the `"gate:MEETING_ID"` channel
  to send commands and receive real-time events for a specific meeting.
  """

  use Phoenix.Socket

  channel "gate:*", ZoomGate.GateChannel

  @impl true
  def connect(params, socket, _connect_info) do
    # TODO: API key authentication
    {:ok, assign(socket, :api_key, params["api_key"])}
  end

  @impl true
  def id(_socket), do: nil
end
