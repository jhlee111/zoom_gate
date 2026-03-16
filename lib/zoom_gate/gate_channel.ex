defmodule ZoomGate.GateChannel do
  @moduledoc """
  Phoenix Channel for real-time meeting control.

  ## Usage (JavaScript client)

      const socket = new Socket("ws://host:4000/ws/gate", {params: {api_key: "..."}})
      socket.connect()

      const channel = socket.channel("gate:123456789")
      channel.join()

      // Send commands
      channel.push("admit", {zoom_user_id: 12345, display_name: "홍길동"})
      channel.push("deny", {zoom_user_id: 12345, message: "Not authorized"})

      // Receive events
      channel.on("waiting_room_join", ({zoom_user_id, display_name}) => ...)
      channel.on("participant_joined", ({zoom_user_id, display_name}) => ...)
      channel.on("meeting_ended", () => ...)
  """

  use Phoenix.Channel

  require Logger

  @impl true
  def join("gate:" <> meeting_id, _params, socket) do
    case ZoomGate.Session.whereis(meeting_id) do
      nil ->
        {:error, %{reason: "no active session for meeting #{meeting_id}"}}

      _pid ->
        # Subscribe to session events via Registry
        # The session will deliver events to this channel process
        send(self(), :subscribe_to_session)
        {:ok, assign(socket, :meeting_id, meeting_id)}
    end
  end

  @impl true
  def handle_in("admit", %{"zoom_user_id" => zid} = params, socket) do
    opts = if params["display_name"], do: [display_name: params["display_name"]], else: []
    ZoomGate.Session.admit(socket.assigns.meeting_id, zid, opts)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("deny", %{"zoom_user_id" => zid} = params, socket) do
    opts = if params["message"], do: [message: params["message"]], else: []
    ZoomGate.Session.deny(socket.assigns.meeting_id, zid, opts)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("rename", %{"zoom_user_id" => zid, "display_name" => name}, socket) do
    ZoomGate.Session.rename(socket.assigns.meeting_id, zid, name)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("expel", %{"zoom_user_id" => zid}, socket) do
    ZoomGate.Session.expel(socket.assigns.meeting_id, zid)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("chat", %{"message" => msg} = params, socket) do
    opts = if params["to"], do: [to: params["to"]], else: []
    ZoomGate.Session.send_chat(socket.assigns.meeting_id, msg, opts)
    {:reply, :ok, socket}
  end

  # Forward session events to the WebSocket client
  @impl true
  def handle_info({:zoom_gate, {event_type, payload}}, socket) do
    push(socket, to_string(event_type), payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:subscribe_to_session, socket) do
    meeting_id = socket.assigns.meeting_id

    case ZoomGate.Session.whereis(meeting_id) do
      nil ->
        {:noreply, socket}

      pid ->
        ZoomGate.Session.subscribe(meeting_id)
        Process.monitor(pid)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    push(socket, "meeting_ended", %{reason: "session_terminated"})
    {:stop, :normal, socket}
  end
end
