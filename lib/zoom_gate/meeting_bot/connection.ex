defmodule ZoomGate.MeetingBot.Connection do
  @moduledoc """
  HTTP connection flow for Zoom RWG WebSocket.

  Executes the three-step connection:

      1. GET zoom.us/api/v1/wc/info → meeting info + RWC servers
      2. GET rwc/wc/ping/{meeting} → RWG hostname + rwcAuth
      3. WSS rwg/wc/api/{meeting}?as_type=1&... → WebSocket connection
  """

  require Logger

  @user_agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
  @user_agent_short "Chrome130"

  @doc """
  Execute the full connection flow.

  `config` must be a map/struct with: `meeting_number`, `meeting_password`,
  `display_name`, `sdk_key`, `sdk_secret`, `hardware_id`.

  Returns `{:ok, conn, stream_ref, meeting_info}` or `{:error, reason}`.
  """
  def connect(config) do
    with {:ok, meeting_info, cookies} <- get_meeting_info(config),
         {:ok, rwg_info} <- ping_rwc(meeting_info),
         {:ok, conn, stream_ref} <- connect_websocket(config, meeting_info, rwg_info, cookies) do
      {:ok, conn, stream_ref, meeting_info}
    end
  end

  @doc """
  Reconnect to RWG with existing meeting info (used after waiting room admit).

  `extra_params` are merged into the WebSocket query string (e.g., opt, zoomid, participantID).
  """
  def reconnect(config, meeting_info, rwg_info, cookies, extra_params \\ %{}) do
    connect_websocket(config, meeting_info, rwg_info, cookies, extra_params)
  end

  @doc "Step 1: Get meeting info from Zoom API."
  def get_meeting_info(config) do
    role = Map.get(config, :role, 0)
    signature = generate_signature(config.sdk_key, config.sdk_secret, config.meeting_number, role)

    params =
      URI.encode_query(%{
        "meetingNumber" => config.meeting_number,
        "userName" => config.display_name,
        "passWord" => config.meeting_password,
        "signature" => signature,
        "apiKey" => config.sdk_key,
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

  @doc "Step 2: Ping RWC server to get RWG hostname."
  def ping_rwc(meeting_info) do
    encrypted_rwc = parse_encrypted_rwc(meeting_info["encryptedRWC"])

    case Map.to_list(encrypted_rwc) do
      [{rwc_domain, rwc_token} | _] ->
        url =
          "https://#{rwc_domain}/wc/ping/#{meeting_info["meetingNumber"]}?ts=#{meeting_info["ts"]}&auth=#{meeting_info["auth"]}&rwcToken=#{rwc_token}&dmz=1"

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

  @doc "Step 3: Connect WebSocket to RWG server."
  def connect_websocket(config, meeting_info, rwg_info, cookies, extra_params \\ %{}) do
    base_params = %{
      "dn2" => Base.encode64(meeting_info["userName"] || config.display_name),
      "browser" => @user_agent_short,
      "trackAuth" => meeting_info["track_auth"] || "",
      "mid" => meeting_info["mid"] || "",
      "tid" => meeting_info["tid"] || "",
      "lang" => "en",
      "ts" => to_string(meeting_info["ts"] || ""),
      "auth" => meeting_info["auth"] || "",
      "sign" => meeting_info["sign"] || "",
      "ZM-CID" => config.hardware_id,
      "_ZM_MTG_TRACK_ID" => "",
      "jscv" => "5.1.4",
      "fromNginx" => "undefined",
      "mpwd" => meeting_info["passWord"] || config.meeting_password,
      "zak" => Map.get(config, :zak, ""),
      "signType" => "sdk",
      "rwcAuth" => rwg_info["rwcAuth"] || "",
      "as_type" => to_string(Map.get(config, :as_type, 1)),
      "email" => "0",
      "tk" => "",
      "cfs" => "0",
      "clientCaps" => "595"
    }

    params = URI.encode_query(Map.merge(base_params, extra_params))
    rwg_host = rwg_info["rwg"]
    ws_path = "/wc/api/#{config.meeting_number}?#{params}"

    Logger.info("[Connection] Connecting to wss://#{rwg_host}#{ws_path}")

    with {:ok, conn} <-
           :gun.open(String.to_charlist(rwg_host), 443, %{
             transport: :tls,
             tls_opts: [verify: :verify_none],
             protocols: [:http]
           }),
         {:ok, :http} <- :gun.await_up(conn, 10_000) do
      stream_ref =
        :gun.ws_upgrade(conn, String.to_charlist(ws_path), [
          {~c"user-agent", String.to_charlist(@user_agent)},
          {~c"origin", ~c"http://localhost:9999"},
          {~c"cookie", String.to_charlist(cookies)}
        ])

      await_ws_upgrade(conn, stream_ref)
    end
  end

  # -- Private --

  defp await_ws_upgrade(conn, stream_ref) do
    receive do
      {:gun_upgrade, ^conn, ^stream_ref, ["websocket"], _headers} ->
        {:ok, conn, stream_ref}

      {:gun_upgrade, ^conn, ^stream_ref, _, _headers} ->
        {:ok, conn, stream_ref}

      {:gun_response, ^conn, _, _, status, _} ->
        :gun.close(conn)
        {:error, "WS upgrade failed: #{status}"}

      {:gun_error, ^conn, _, reason} ->
        :gun.close(conn)
        {:error, "WS error: #{inspect(reason)}"}
    after
      10_000 ->
        :gun.close(conn)
        {:error, :ws_timeout}
    end
  end

  defp generate_signature(sdk_key, sdk_secret, meeting_number, role) do
    now = System.system_time(:second)

    header = Jason.encode!(%{"alg" => "HS256", "typ" => "JWT"})

    payload =
      Jason.encode!(%{
        "sdkKey" => sdk_key,
        "iat" => now,
        "exp" => now + 1800,
        "mn" => meeting_number,
        "role" => role
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
