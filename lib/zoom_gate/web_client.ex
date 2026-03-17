defmodule ZoomGate.WebClient do
  @moduledoc """
  Pure Elixir Zoom Web SDK client.

  Connects directly to Zoom's RWG WebSocket without a browser.
  Uses `as_type=1` (plaintext JSON) — no binary framing, no encryption.

  Based on the Zoomer (Go) reverse-engineering: https://github.com/chris124567/zoomer

  ## Flow

      1. Generate SDK JWT signature
      2. GET zoom.us/api/v1/wc/info → meeting info + RWC servers
      3. GET rwc/wc/ping/{meeting} → RWG hostname + rwcAuth
      4. WSS rwg/wc/api/{meeting}?as_type=1&... → JSON messages
      5. Send/receive {evt: N, body: {...}, seq: M}
  """

  use GenServer
  require Logger

  @user_agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
  @user_agent_short "Chrome130"
  @keepalive_interval 60_000

  # evt codes
  @evt_keepalive 0
  @evt_join_res 4098
  @evt_roster 7937
  @evt_attribute 7938
  @evt_end 7939
  @evt_host_change 7940
  @evt_hold_change 7942
  @evt_chat_indication 7944
  @evt_option 7945

  @evt_rename_req 4109
  @evt_chat_req 4135
  @evt_expel_req 4107
  @evt_put_on_hold_req 4113
  @evt_admit_all_req 4199
  @evt_end_req 4101
  @evt_leave_req 4103
  @evt_mute_req 8193
  @evt_assign_host_req 4111

  defstruct [
    :meeting_number,
    :meeting_password,
    :display_name,
    :sdk_key,
    :sdk_secret,
    :callback,
    :conn,
    :stream,
    :join_info,
    :hardware_id,
    seq: 0,
    status: :disconnected,
    participants: %{},
    waiting_room: %{}
  ]

  # -- Public API --

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def rename(pid, user_id, old_name, new_name) do
    GenServer.call(pid, {:rename, user_id, old_name, new_name})
  end

  def send_chat(pid, dest_node_id \\ 0, text) do
    GenServer.call(pid, {:chat, dest_node_id, text})
  end

  def expel(pid, user_id) do
    GenServer.call(pid, {:expel, user_id})
  end

  def admit_all(pid) do
    GenServer.call(pid, :admit_all)
  end

  def leave(pid) do
    GenServer.call(pid, :leave)
  end

  # -- GenServer --

  @impl true
  def init(opts) do
    state = %__MODULE__{
      meeting_number: Keyword.fetch!(opts, :meeting_number),
      meeting_password: Keyword.get(opts, :password, ""),
      display_name: Keyword.get(opts, :display_name, "ZoomGate-Bot"),
      sdk_key: Keyword.fetch!(opts, :sdk_key),
      sdk_secret: Keyword.fetch!(opts, :sdk_secret),
      callback: Keyword.get(opts, :callback),
      hardware_id: UUID.uuid4()
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case do_connect(state) do
      {:ok, new_state} ->
        schedule_keepalive()
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("[WebClient] Connection failed: #{inspect(reason)}")
        notify(state, {:error, %{message: "Connection failed: #{inspect(reason)}"}})
        {:stop, {:connection_failed, reason}, state}
    end
  end

  @impl true
  def handle_call({:rename, user_id, old_name, new_name}, _from, state) do
    state = send_evt(state, @evt_rename_req, %{
      id: user_id,
      dn2: Base.url_encode64(new_name, padding: false),
      olddn2: Base.url_encode64(old_name, padding: false)
    })
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:chat, dest_node_id, text}, _from, state) do
    state = send_evt(state, @evt_chat_req, %{
      destNodeID: dest_node_id,
      sn: Base.url_encode64(state.join_info["zoomID"] || "", padding: false),
      text: Base.url_encode64(text, padding: false)
    })
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:expel, user_id}, _from, state) do
    state = send_evt(state, @evt_expel_req, %{id: user_id})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:admit_all, _from, state) do
    state = send_evt(state, @evt_admit_all_req, %{})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:leave, _from, state) do
    state = send_evt(state, @evt_leave_req, %{})
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:keepalive, state) do
    state = send_evt(state, @evt_keepalive, nil)
    schedule_keepalive()
    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_ws, _conn, _stream, {:text, data}}, state) do
    case Jason.decode(data) do
      {:ok, msg} ->
        state = handle_zoom_message(msg, state)
        {:noreply, state}

      {:error, _} ->
        Logger.warning("[WebClient] Unparseable message: #{data}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:gun_ws, _conn, _stream, {:close, code, reason}}, state) do
    Logger.info("[WebClient] WebSocket closed: #{code} #{reason}")
    notify(state, {:meeting_ended, %{reason: :ws_closed}})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:gun_down, _conn, _proto, reason, _}, state) do
    Logger.error("[WebClient] Connection down: #{inspect(reason)}")
    {:stop, {:connection_down, reason}, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[WebClient] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # -- Connection Flow --

  defp do_connect(state) do
    with {:ok, meeting_info, cookies} <- get_meeting_info(state),
         {:ok, rwg_info} <- ping_rwc(state, meeting_info),
         {:ok, conn, state} <- connect_websocket(state, meeting_info, rwg_info, cookies) do
      {:ok, %{state | conn: conn, status: :connected}}
    end
  end

  defp get_meeting_info(state) do
    signature = generate_signature(state.sdk_key, state.sdk_secret, state.meeting_number)

    params = URI.encode_query(%{
      "meetingNumber" => state.meeting_number,
      "userName" => state.display_name,
      "passWord" => state.meeting_password,
      "signature" => signature,
      "apiKey" => state.sdk_key,
      "lang" => "en-US",
      "userEmail" => "",
      "cv" => "5.1.4",
      "proxy" => "1",
      "sdkOrigin" => Base.url_encode64("http://localhost:9999", padding: false),
      "sdkUrl" => Base.url_encode64("http://localhost:9999/meeting.html", padding: false),
      "tk" => "",
      "ztk" => "",
      "captcha" => "",
      "captchaName" => "",
      "suid" => "",
      "callback" => "axiosJsonpCallback1",
      "signatureType" => "sdk"
    })

    url = "https://zoom.us/api/v1/wc/info?#{params}"

    case :httpc.request(:get, {String.to_charlist(url), headers_charlist()}, ssl_opts(), []) do
      {:ok, {{_, 200, _}, resp_headers, body}} ->
        body_str = IO.iodata_to_binary(body)
        # Extract JSONP callback wrapper
        json_str = extract_jsonp(body_str)

        case Jason.decode(json_str) do
          {:ok, %{"status" => true, "result" => result}} ->
            cookies = extract_cookies(resp_headers)
            {:ok, result, cookies}

          {:ok, %{"errorCode" => code, "errorMessage" => msg}} ->
            {:error, "Meeting info error #{code}: #{msg}"}

          {:error, err} ->
            {:error, "JSON parse error: #{inspect(err)}"}
        end

      {:ok, {{_, status, _}, _, _}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ping_rwc(_state, meeting_info) do
    encrypted_rwc = parse_encrypted_rwc(meeting_info["encryptedRWC"])

    case Map.to_list(encrypted_rwc) do
      [{rwc_domain, rwc_token} | _] ->
        url = "https://#{rwc_domain}/wc/ping/#{meeting_info["meetingNumber"]}?ts=#{meeting_info["ts"]}&auth=#{meeting_info["auth"]}&rwcToken=#{rwc_token}&dmz=1"

        case :httpc.request(:get, {String.to_charlist(url), headers_charlist()}, ssl_opts(), []) do
          {:ok, {{_, 200, _}, _, body}} ->
            Jason.decode(IO.iodata_to_binary(body))

          {:ok, {{_, status, _}, _, _}} ->
            {:error, "Ping HTTP #{status}"}

          {:error, reason} ->
            {:error, reason}
        end

      [] ->
        {:error, "No RWC servers"}
    end
  end

  defp connect_websocket(state, meeting_info, rwg_info, cookies) do
    params = URI.encode_query(%{
      "dn2" => Base.encode64(meeting_info["userName"] || state.display_name),
      "browser" => @user_agent_short,
      "trackAuth" => meeting_info["track_auth"] || "",
      "mid" => meeting_info["mid"] || "",
      "tid" => meeting_info["tid"] || "",
      "lang" => "en",
      "ts" => to_string(meeting_info["ts"] || ""),
      "auth" => meeting_info["auth"] || "",
      "sign" => meeting_info["sign"] || "",
      "ZM-CID" => state.hardware_id,
      "_ZM_MTG_TRACK_ID" => "",
      "jscv" => "5.1.4",
      "fromNginx" => "undefined",
      "mpwd" => meeting_info["passWord"] || state.meeting_password,
      "zak" => "",
      "signType" => "sdk",
      "rwcAuth" => rwg_info["rwcAuth"] || "",
      "as_type" => "1",
      "email" => "0",
      "tk" => "",
      "cfs" => "0",
      "clientCaps" => "595"
    })

    rwg_host = rwg_info["rwg"]
    ws_path = "/wc/api/#{state.meeting_number}?#{params}"

    Logger.info("[WebClient] Connecting to wss://#{rwg_host}#{ws_path}")

    {:ok, conn} = :gun.open(String.to_charlist(rwg_host), 443, %{
      transport: :tls,
      tls_opts: [verify: :verify_none],
      protocols: [:http]
    })

    {:ok, :http} = :gun.await_up(conn, 10_000)

    stream_ref = :gun.ws_upgrade(conn, String.to_charlist(ws_path), [
      {~c"user-agent", String.to_charlist(@user_agent)},
      {~c"origin", ~c"http://localhost:9999"},
      {~c"cookie", String.to_charlist(cookies)}
    ])

    receive do
      {:gun_upgrade, ^conn, ^stream_ref, ["websocket"], _headers} ->
        Logger.info("[WebClient] WebSocket connected!")
        {:ok, conn, %{state | stream: stream_ref}}

      {:gun_upgrade, ^conn, ^stream_ref, _, _headers} ->
        Logger.info("[WebClient] WebSocket connected (alt match)")
        {:ok, conn, %{state | stream: stream_ref}}

      {:gun_response, ^conn, _, _, status, _} ->
        {:error, "WS upgrade failed: #{status}"}

      {:gun_error, ^conn, _, reason} ->
        {:error, "WS error: #{inspect(reason)}"}
    after
      10_000 -> {:error, :ws_timeout}
    end
  end

  # -- Message Handling --

  defp handle_zoom_message(%{"evt" => @evt_keepalive} = msg, state) do
    Logger.debug("[WebClient] Heartbeat seq=#{msg["seq"]}")
    state
  end

  defp handle_zoom_message(%{"evt" => @evt_join_res, "body" => body}, state) do
    Logger.info("[WebClient] Joined! participantID=#{body["participantID"]} role=#{body["role"]}")
    notify(state, {:bot_joined, %{
      meeting_id: state.meeting_number,
      participant_id: body["participantID"],
      user_id: body["userID"],
      role: body["role"]
    }})
    %{state | join_info: body, status: :active}
  end

  defp handle_zoom_message(%{"evt" => @evt_roster, "body" => body}, state) do
    state = handle_roster(body, state)
    state
  end

  defp handle_zoom_message(%{"evt" => @evt_hold_change, "body" => body}, state) do
    user_id = body["id"]
    b_hold = body["bHold"]

    if b_hold do
      notify(state, {:waiting_room_join, %{zoom_user_id: user_id}})
      put_in(state.waiting_room[user_id], %{zoom_user_id: user_id})
    else
      notify(state, {:waiting_room_leave, %{zoom_user_id: user_id}})
      %{state | waiting_room: Map.delete(state.waiting_room, user_id)}
    end
  end

  defp handle_zoom_message(%{"evt" => @evt_chat_indication, "body" => body}, state) do
    text = case body["text"] do
      t when is_binary(t) -> Base.url_decode64!(t, padding: false)
      _ -> ""
    end

    notify(state, {:chat_received, %{
      from_user_id: body["senderSN"],
      message: text
    }})
    state
  end

  defp handle_zoom_message(%{"evt" => @evt_end}, state) do
    Logger.info("[WebClient] Meeting ended")
    notify(state, {:meeting_ended, %{reason: :host_ended}})
    %{state | status: :ended}
  end

  defp handle_zoom_message(%{"evt" => @evt_host_change, "body" => body}, state) do
    Logger.info("[WebClient] Host changed to #{body["id"]}")
    notify(state, {:host_changed, %{new_host_id: body["id"]}})
    state
  end

  defp handle_zoom_message(%{"evt" => evt}, state) do
    Logger.debug("[WebClient] Unhandled evt=#{evt}")
    state
  end

  defp handle_roster(%{"add" => adds} = body, state) when is_list(adds) do
    state = Enum.reduce(adds, state, fn user, acc ->
      user_id = user["id"]
      display_name = decode_b64(user["dn2"])
      notify(acc, {:participant_joined, %{zoom_user_id: user_id, display_name: display_name}})
      %{acc | participants: Map.put(acc.participants, user_id, %{zoom_user_id: user_id, display_name: display_name})}
    end)

    handle_roster(Map.delete(body, "add"), state)
  end

  defp handle_roster(%{"update" => updates} = body, state) when is_list(updates) do
    state = Enum.reduce(updates, state, fn user, acc ->
      user_id = user["id"]
      display_name = decode_b64(user["dn2"])

      if display_name != "" do
        %{acc | participants: Map.put(acc.participants, user_id, %{zoom_user_id: user_id, display_name: display_name})}
      else
        acc
      end
    end)

    handle_roster(Map.delete(body, "update"), state)
  end

  defp handle_roster(%{"remove" => removes} = body, state) when is_list(removes) do
    state = Enum.reduce(removes, state, fn user, acc ->
      user_id = user["id"]
      notify(acc, {:participant_left, %{zoom_user_id: user_id}})
      %{acc | participants: Map.delete(acc.participants, user_id)}
    end)

    handle_roster(Map.delete(body, "remove"), state)
  end

  defp handle_roster(_body, state), do: state

  # -- Helpers --

  defp send_evt(state, evt, body) do
    seq = state.seq + 1
    msg = %{"evt" => evt, "seq" => seq}
    msg = if body, do: Map.put(msg, "body", body), else: msg

    :gun.ws_send(state.conn, state.stream, {:text, Jason.encode!(msg)})
    %{state | seq: seq}
  end

  defp schedule_keepalive do
    Process.send_after(self(), :keepalive, @keepalive_interval)
  end

  defp notify(%{callback: nil}, _event), do: :ok
  defp notify(%{callback: pid}, event) when is_pid(pid), do: send(pid, {:zoom_gate, event})
  defp notify(%{callback: {mod, fun}}, event), do: apply(mod, fun, [event])
  defp notify(_, _), do: :ok

  defp generate_signature(sdk_key, sdk_secret, meeting_number) do
    now = System.system_time(:second)
    header = Jason.encode!(%{"alg" => "HS256", "typ" => "JWT"})
    payload = Jason.encode!(%{
      "sdkKey" => sdk_key,
      "iat" => now,
      "exp" => now + 1800,
      "mn" => meeting_number,
      "role" => 0
    })

    h = Base.url_encode64(header, padding: true)
    p = Base.url_encode64(payload, padding: true)
    message = "#{h}.#{p}"

    sig = :crypto.mac(:hmac, :sha256, sdk_secret, message) |> Base.url_encode64(padding: true)
    "#{message}.#{sig}"
  end

  defp extract_jsonp(body) do
    case Regex.run(~r/axiosJsonpCallback1\((.+)\)/, body, capture: :all_but_first) do
      [json] -> json
      _ -> body
    end
  end

  defp parse_encrypted_rwc(rwc) when is_binary(rwc) do
    case Jason.decode(rwc) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end
  defp parse_encrypted_rwc(rwc) when is_map(rwc), do: rwc
  defp parse_encrypted_rwc(_), do: %{}

  defp extract_cookies(headers) do
    headers
    |> Enum.filter(fn {k, _} -> String.downcase(to_string(k)) == "set-cookie" end)
    |> Enum.map(fn {_, v} ->
      to_string(v) |> String.split(";") |> hd()
    end)
    |> Enum.join("; ")
  end

  defp decode_b64(nil), do: ""
  defp decode_b64(str) when is_binary(str) do
    case Base.url_decode64(str, padding: false) do
      {:ok, decoded} -> decoded
      _ -> str
    end
  end

  defp headers_charlist do
    [
      {~c"user-agent", String.to_charlist(@user_agent)},
      {~c"accept", ~c"application/json, text/plain, */*"},
      {~c"accept-language", ~c"en-US,en;q=0.9"}
    ]
  end

  defp ssl_opts do
    [{:ssl, [verify: :verify_none]}]
  end
end
