defmodule ZoomGate.SdkJwtTest do
  use ExUnit.Case, async: true

  alias ZoomGate.SdkJwt

  describe "generate/3" do
    test "produces a valid 3-part JWT" do
      token = SdkJwt.generate("test_key", "test_secret")
      parts = String.split(token, ".")
      assert length(parts) == 3
    end

    test "header is HS256 JWT" do
      token = SdkJwt.generate("test_key", "test_secret")
      [header_b64 | _] = String.split(token, ".")
      {:ok, header_json} = Base.url_decode64(header_b64, padding: false)
      header = Jason.decode!(header_json)
      assert header["alg"] == "HS256"
      assert header["typ"] == "JWT"
    end

    test "payload contains appKey and timestamps" do
      token = SdkJwt.generate("my_key", "my_secret", 3600)
      [_, payload_b64 | _] = String.split(token, ".")
      {:ok, payload_json} = Base.url_decode64(payload_b64, padding: false)
      payload = Jason.decode!(payload_json)

      assert payload["appKey"] == "my_key"
      assert is_integer(payload["iat"])
      assert is_integer(payload["exp"])
      assert payload["exp"] - payload["iat"] == 3600
    end

    test "signature is verifiable with HMAC-SHA256" do
      secret = "test_secret_123"
      token = SdkJwt.generate("key", secret)
      [header_b64, payload_b64, sig_b64] = String.split(token, ".")

      signing_input = header_b64 <> "." <> payload_b64

      expected_sig =
        :crypto.mac(:hmac, :sha256, secret, signing_input) |> Base.url_encode64(padding: false)

      assert sig_b64 == expected_sig
    end
  end
end
