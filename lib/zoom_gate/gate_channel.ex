defmodule ZoomGate.GateChannel do
  @moduledoc """
  Phoenix Channel for real-time meeting control.

  ## Usage (JavaScript client)

      const socket = new Socket("ws://host:4000/ws/gate", {params: {api_key: "..."}})
      socket.connect()

      const channel = socket.channel("gate:123456789")
      channel.join()

      // Query state
      channel.push("get_status", {}).receive("ok", (status) => ...)
      channel.push("get_participants", {}).receive("ok", (list) => ...)
      channel.push("get_waiting_room", {}).receive("ok", (list) => ...)

      // Send commands
      channel.push("admit", {zoom_user_id: 12345})
      channel.push("deny", {zoom_user_id: 12345})
      channel.push("rename", {zoom_user_id: 12345, display_name: "New Name"})
      channel.push("admit_all", {})
      channel.push("mute", {zoom_user_id: 12345})
      channel.push("end_meeting", {})
      channel.push("start_recording", {})
      channel.push("stop_recording", {})
      channel.push("lock_sharing", {locked: true})
      channel.push("spotlight", {zoom_user_id: 12345})

      // Receive events
      channel.on("waiting_room_join", ({zoom_user_id, display_name}) => ...)
      channel.on("participant_joined", ({zoom_user_id, display_name}) => ...)
      channel.on("meeting_ended", () => ...)
  """

  use Phoenix.Channel

  require Logger

  @doc false
  @impl true
  def join("gate:" <> meeting_id, _params, socket) do
    case ZoomGate.Session.whereis(meeting_id) do
      nil ->
        {:error, %{reason: "no active session for meeting #{meeting_id}"}}

      _pid ->
        send(self(), :subscribe_to_session)
        {:ok, assign(socket, :meeting_id, meeting_id)}
    end
  end

  @doc false
  @impl true
  def handle_in("get_status", _params, socket) do
    status = ZoomGate.Session.get_status(socket.assigns.meeting_id)
    {:reply, {:ok, status}, socket}
  end

  @doc false
  @impl true
  def handle_in("get_participants", _params, socket) do
    status = ZoomGate.Session.get_status(socket.assigns.meeting_id)
    {:reply, {:ok, %{participants: status.participants}}, socket}
  end

  @doc false
  @impl true
  def handle_in("get_waiting_room", _params, socket) do
    status = ZoomGate.Session.get_status(socket.assigns.meeting_id)
    {:reply, {:ok, %{waiting_room: status.waiting_room}}, socket}
  end

  @doc false
  @impl true
  def handle_in("admit", %{"zoom_user_id" => zid} = params, socket) do
    opts = if params["display_name"], do: [display_name: params["display_name"]], else: []
    ZoomGate.Session.admit(socket.assigns.meeting_id, zid, opts)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("deny", %{"zoom_user_id" => zid} = params, socket) do
    opts = if params["message"], do: [message: params["message"]], else: []
    ZoomGate.Session.deny(socket.assigns.meeting_id, zid, opts)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("rename", %{"zoom_user_id" => zid, "display_name" => name}, socket) do
    ZoomGate.Session.rename(socket.assigns.meeting_id, zid, name)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("expel", %{"zoom_user_id" => zid}, socket) do
    ZoomGate.Session.expel(socket.assigns.meeting_id, zid)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("chat", %{"message" => msg} = params, socket) do
    opts = if params["to"], do: [to: params["to"]], else: []
    ZoomGate.Session.send_chat(socket.assigns.meeting_id, msg, opts)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("chat_waiting_room", %{"message" => msg}, socket) do
    ZoomGate.Session.chat_waiting_room(socket.assigns.meeting_id, msg)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("admit_all", _params, socket) do
    ZoomGate.Session.admit_all(socket.assigns.meeting_id)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("mute", %{"zoom_user_id" => zid}, socket) do
    ZoomGate.Session.mute(socket.assigns.meeting_id, zid)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("end_meeting", _params, socket) do
    ZoomGate.Session.end_meeting(socket.assigns.meeting_id)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("start_recording", _params, socket) do
    ZoomGate.Session.start_recording(socket.assigns.meeting_id)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("stop_recording", _params, socket) do
    ZoomGate.Session.stop_recording(socket.assigns.meeting_id)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("lock_sharing", %{"locked" => locked}, socket) do
    ZoomGate.Session.lock_sharing(socket.assigns.meeting_id, locked)
    {:reply, :ok, socket}
  end

  @doc false
  @impl true
  def handle_in("spotlight", %{"zoom_user_id" => zid} = params, socket) do
    spotlight = Map.get(params, "spotlight", true)
    ZoomGate.Session.spotlight(socket.assigns.meeting_id, zid, spotlight)
    {:reply, :ok, socket}
  end

  # Forward session events to the WebSocket client
  @doc false
  @impl true
  def handle_info({:zoom_gate, {event_type, payload}}, socket) do
    push(socket, to_string(event_type), payload)
    {:noreply, socket}
  end

  @doc false
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

  @doc false
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    push(socket, "meeting_ended", %{reason: "session_terminated"})
    {:stop, :normal, socket}
  end
end
