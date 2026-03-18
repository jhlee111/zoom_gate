defmodule ZoomGate.ZoomAPI do
  @moduledoc """
  Zoom REST API client using Server-to-Server OAuth.

  Handles OAuth token acquisition, meeting creation, and ZAK token retrieval.
  Credentials are read from application config (sourced from `.env` via Dotenvy).

  ## Usage

      {:ok, token} = ZoomGate.ZoomAPI.get_access_token()
      {:ok, meeting} = ZoomGate.ZoomAPI.create_meeting(token)
      {:ok, zak} = ZoomGate.ZoomAPI.get_zak(token)
  """

  @token_url ~c"https://zoom.us/oauth/token"
  @api_base ~c"https://api.zoom.us/v2"

  @doc """
  Get an S2S OAuth access token using account credentials.

  Returns `{:ok, access_token}` or `{:error, reason}`.
  """
  @spec get_access_token() :: {:ok, String.t()} | {:error, term()}
  def get_access_token do
    account_id = config!(:zoom_account_id)
    client_id = config!(:zoom_client_id)
    client_secret = config!(:zoom_client_secret)

    credentials = Base.encode64("#{client_id}:#{client_secret}")
    url = @token_url ++ ~c"?grant_type=account_credentials&account_id=#{account_id}"

    headers = [
      {~c"authorization", ~c"Basic #{credentials}"},
      {~c"content-type", ~c"application/x-www-form-urlencoded"}
    ]

    case :httpc.request(
           :post,
           {url, headers, ~c"application/x-www-form-urlencoded", ~c""},
           ssl_opts(),
           []
         ) do
      {:ok, {{_, 200, _}, _, body}} ->
        {:ok, %{"access_token" => token}} = Jason.decode(to_string(body))
        {:ok, token}

      {:ok, {{_, status, _}, _, body}} ->
        {:error, {status, to_string(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a Zoom meeting.

  ## Options

    * `:topic` — meeting topic (default: "ZoomGate Session")
    * `:duration` — duration in minutes (default: 60)
    * `:waiting_room` — enable waiting room (default: true)
    * `:user_id` — user to create meeting for (default: "me")

  Returns `{:ok, meeting_info}` with keys: `meeting_id`, `password`,
  `encrypted_password`, `join_url`, `topic`.
  """
  @spec create_meeting(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_meeting(access_token, opts \\ []) do
    user_id = Keyword.get(opts, :user_id, "me")
    url = @api_base ++ ~c"/users/#{user_id}/meetings"

    body =
      Jason.encode!(%{
        topic: Keyword.get(opts, :topic, "ZoomGate Session"),
        type: 2,
        duration: Keyword.get(opts, :duration, 60),
        settings: %{
          waiting_room: Keyword.get(opts, :waiting_room, true),
          join_before_host: true,
          approval_type: 0,
          meeting_authentication: false
        }
      })

    headers = [
      {~c"authorization", ~c"Bearer #{access_token}"},
      {~c"content-type", ~c"application/json"}
    ]

    case :httpc.request(
           :post,
           {url, headers, ~c"application/json", to_charlist(body)},
           ssl_opts(),
           []
         ) do
      {:ok, {{_, 201, _}, _, resp_body}} ->
        {:ok, resp} = Jason.decode(to_string(resp_body))

        {:ok,
         %{
           meeting_id: resp["id"],
           password: resp["password"],
           encrypted_password: resp["encrypted_password"],
           join_url: resp["join_url"],
           topic: resp["topic"]
         }}

      {:ok, {{_, status, _}, _, resp_body}} ->
        {:error, {status, to_string(resp_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a ZAK (Zoom Access Key) token for the authenticated user.

  Required for the MeetingBot to join as a named participant.
  """
  @spec get_zak(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_zak(access_token, user_id \\ "me") do
    url = @api_base ++ ~c"/users/#{user_id}/zak"

    headers = [{~c"authorization", ~c"Bearer #{access_token}"}]

    case :httpc.request(:get, {url, headers}, ssl_opts(), []) do
      {:ok, {{_, 200, _}, _, body}} ->
        {:ok, %{"token" => zak}} = Jason.decode(to_string(body))
        {:ok, zak}

      {:ok, {{_, status, _}, _, body}} ->
        {:error, {status, to_string(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete (end) a meeting.
  """
  @spec delete_meeting(String.t(), integer() | String.t()) :: :ok | {:error, term()}
  def delete_meeting(access_token, meeting_id) do
    url = @api_base ++ ~c"/meetings/#{meeting_id}"
    headers = [{~c"authorization", ~c"Bearer #{access_token}"}]

    case :httpc.request(:delete, {url, headers}, ssl_opts(), []) do
      {:ok, {{_, 204, _}, _, _}} -> :ok
      {:ok, {{_, status, _}, _, body}} -> {:error, {status, to_string(body)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update account-level Zoom settings.

  Requires S2S OAuth scope `account:update:settings:admin`.

  ## Example

      {:ok, token} = ZoomGate.ZoomAPI.get_access_token()
      ZoomGate.ZoomAPI.update_account_settings(token, %{
        "in_meeting" => %{"breakout_room" => true, "waiting_room" => true}
      })
  """
  @spec update_account_settings(String.t(), map()) :: :ok | {:error, term()}
  def update_account_settings(access_token, settings) do
    url = @api_base ++ ~c"/accounts/me/settings"
    body = Jason.encode!(settings)

    headers = [
      {~c"authorization", ~c"Bearer #{access_token}"},
      {~c"content-type", ~c"application/json"}
    ]

    case :httpc.request(
           :patch,
           {url, headers, ~c"application/json", to_charlist(body)},
           ssl_opts(),
           []
         ) do
      {:ok, {{_, status, _}, _, _}} when status in [200, 204] -> :ok
      {:ok, {{_, status, _}, _, resp_body}} -> {:error, {status, to_string(resp_body)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ssl_opts, do: [{:ssl, [{:verify, :verify_none}]}]

  defp config!(key) do
    Application.get_env(:zoom_gate, key) ||
      raise "Missing config :zoom_gate, #{inspect(key)} — add #{key |> Atom.to_string() |> String.upcase()} to .env"
  end
end
