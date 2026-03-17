defmodule ZoomGate.SdkJwt do
  @moduledoc """
  Generates JWT tokens for Zoom Meeting SDK authentication.

  The SDK expects a JWT with:
  - Header: {"alg": "HS256", "typ": "JWT"}
  - Payload: {"appKey": sdk_key, "iat": now, "exp": now + ttl, "tokenExp": now + ttl}
  - Signature: HMAC-SHA256(header.payload, sdk_secret)
  """

  @default_ttl 7200

  @doc """
  Generates a JWT token for SDK authentication.

  Options:
    * `:role` - 0 for participant, 1 for host (default: 1)
    * `:meeting_number` - meeting number (optional, required for web SDK)
  """
  def generate(sdk_key, sdk_secret, ttl \\ @default_ttl, opts \\ []) do
    now = System.system_time(:second) - 30
    role = Keyword.get(opts, :role, 1)

    header = %{"alg" => "HS256", "typ" => "JWT"}

    payload = %{
      "appKey" => sdk_key,
      "sdkKey" => sdk_key,
      "iat" => now,
      "exp" => now + ttl,
      "tokenExp" => now + ttl,
      "role" => role
    }

    header_b64 = base64url_encode(Jason.encode!(header))
    payload_b64 = base64url_encode(Jason.encode!(payload))

    signing_input = header_b64 <> "." <> payload_b64

    signature =
      :crypto.mac(:hmac, :sha256, sdk_secret, signing_input)
      |> base64url_encode()

    signing_input <> "." <> signature
  end

  defp base64url_encode(data) do
    Base.url_encode64(data, padding: false)
  end
end
