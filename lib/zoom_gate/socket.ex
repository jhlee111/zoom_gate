defmodule ZoomGate.Socket do
  @moduledoc """
  Phoenix Socket for WebSocket consumers (Node.js, Python, browsers, etc.).

  Clients connect to `ws://host:4000/ws/gate` and join the `"gate:MEETING_ID"` channel
  to send commands and receive real-time events for a specific meeting.
  """

  use Phoenix.Socket

  channel("gate:*", ZoomGate.GateChannel)

  @impl true
  def connect(params, socket, _connect_info) do
    configured_key = Application.get_env(:zoom_gate, :api_key)

    if is_nil(configured_key) or configured_key == "" do
      {:ok, socket}
    else
      case params["api_key"] do
        key when key == configured_key -> {:ok, socket}
        _ -> :error
      end
    end
  end

  @impl true
  def id(_socket), do: nil
end
