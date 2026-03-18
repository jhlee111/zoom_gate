defmodule ZoomGate.WebhookRouter do
  @moduledoc """
  Handles incoming Zoom S2S webhook events.

  Zoom sends events like `meeting.participant_joined`, `meeting.participant_waiting`,
  etc. to this endpoint. Events are validated using the `ZOOM_SECRET_TOKEN` and
  broadcast via PubSub for consumption by the Analyzer or other subscribers.

  ## Endpoint

      POST /webhooks/zoom

  ## Zoom URL Validation

  When Zoom sends `{"event": "endpoint.url_validation"}`, this endpoint responds
  with the required `plainToken` + HMAC hash to prove ownership.
  """

  use Plug.Router
  require Logger

  plug(:match)
  plug(:dispatch)

  post "/zoom" do
    body = conn.body_params

    case body["event"] do
      "endpoint.url_validation" ->
        handle_url_validation(conn, body)

      event when is_binary(event) ->
        handle_event(conn, event, body)

      _ ->
        send_json(conn, 400, %{error: "unknown_event"})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  # -- Zoom URL Validation Challenge --

  defp handle_url_validation(conn, body) do
    plain_token = body["payload"]["plainToken"]
    secret_token = Application.get_env(:zoom_gate, :zoom_secret_token)

    encrypted_token =
      :crypto.mac(:hmac, :sha256, secret_token, plain_token)
      |> Base.encode16(case: :lower)

    Logger.info("[Webhook] URL validation challenge responded")

    send_json(conn, 200, %{
      plainToken: plain_token,
      encryptedToken: encrypted_token
    })
  end

  # -- Event Handling --

  defp handle_event(conn, "meeting.participant_joined_waiting_room", body) do
    {meeting_id, participant} = extract_participant(body)

    Logger.info(
      "[Webhook] #{participant.user_name} entered waiting room | meeting=#{meeting_id} email=#{participant.email} registrant_id=#{participant.registrant_id}"
    )

    broadcast_event(meeting_id, :participant_waiting, participant)
    send_json(conn, 200, %{status: "ok"})
  end

  defp handle_event(conn, "meeting.participant_admitted", body) do
    {meeting_id, participant} = extract_participant(body)
    Logger.info("[Webhook] #{participant.user_name} admitted | meeting=#{meeting_id}")
    broadcast_event(meeting_id, :participant_admitted, participant)
    send_json(conn, 200, %{status: "ok"})
  end

  defp handle_event(conn, "meeting.participant_joined", body) do
    {meeting_id, participant} = extract_participant(body)

    Logger.info(
      "[Webhook] #{participant.user_name} joined | meeting=#{meeting_id} user_id=#{participant.user_id}"
    )

    broadcast_event(meeting_id, :participant_joined, participant)
    send_json(conn, 200, %{status: "ok"})
  end

  defp handle_event(conn, "meeting.participant_left", body) do
    {meeting_id, participant} = extract_participant(body)

    Logger.info(
      "[Webhook] #{participant.user_name} left | meeting=#{meeting_id} reason=#{participant.leave_reason}"
    )

    broadcast_event(meeting_id, :participant_left, participant)
    send_json(conn, 200, %{status: "ok"})
  end

  defp handle_event(conn, event, body) do
    payload = body["payload"] || %{}
    object = payload["object"] || %{}
    meeting_id = to_string(object["id"] || "")
    Logger.info("[Webhook] #{event} | meeting=#{meeting_id}")
    broadcast_event(meeting_id, :raw, %{event: event, payload: payload})
    send_json(conn, 200, %{status: "ok"})
  end

  defp extract_participant(body) do
    payload = body["payload"] || %{}
    object = payload["object"] || %{}
    meeting_id = to_string(object["id"] || "")
    p = object["participant"] || %{}

    participant = %{
      email: p["email"],
      user_name: p["user_name"],
      user_id: p["user_id"],
      registrant_id: p["registrant_id"],
      participant_uuid: p["participant_uuid"],
      join_time: p["join_time"] || p["date_time"],
      leave_reason: p["leave_reason"],
      leave_time: p["leave_time"]
    }

    {meeting_id, participant}
  end

  defp broadcast_event(meeting_id, event_type, data) do
    Phoenix.PubSub.broadcast(ZoomGate.PubSub, "zoom:webhooks", {:zoom_webhook, event_type, data})

    if meeting_id != "" do
      Phoenix.PubSub.broadcast(
        ZoomGate.PubSub,
        "zoom:webhooks:#{meeting_id}",
        {:zoom_webhook, event_type, data}
      )
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
