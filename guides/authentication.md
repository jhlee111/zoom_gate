# Authentication & Security

ZoomGate has two layers of authentication: an **API key** that protects
the ZoomGate service itself, and **Zoom SDK credentials** that authenticate
the bot with Zoom's servers.

## API Key

The API key is optional. Set it via the `ZOOM_GATE_API_KEY` environment
variable (or `config :zoom_gate, api_key: "..."`). If not set or set to
an empty string, **all requests are allowed through** with no authentication.

### REST API

Pass the key as a Bearer token in the `Authorization` header:

```bash
curl -X POST http://localhost:4000/api/sessions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"meeting_id": "123456789"}'
```

On mismatch or missing header, the server returns:

```
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{"error": "unauthorized"}
```

### WebSocket

Pass the key in the connection params when connecting:

```javascript
const socket = new Socket("ws://host:4000/ws/gate", {
  params: { api_key: "YOUR_API_KEY" }
})
socket.connect()
```

If the key is wrong or missing, the WebSocket connection is rejected
(the `connect/3` callback returns `:error`).

### BEAM Cluster API

The BEAM API (`ZoomGate.join_meeting/2`, `ZoomGate.admit/3`, etc.) does
**not** check the API key. It runs inside the BEAM VM with full trust.
Protect cluster access via Erlang distribution cookies and network policies.

## Zoom SDK Credentials

Three credentials are needed to join a meeting as a bot:

| Credential | Env Var | Description |
|------------|---------|-------------|
| SDK Key | `ZOOM_SDK_KEY` | App key from Zoom Marketplace "Meeting SDK" app |
| SDK Secret | `ZOOM_SDK_SECRET` | App secret (used to sign JWTs for RWG auth) |
| ZAK Token | `ZOOM_ZAK` | Per-user token for host-level access |

### Providing Credentials

Credentials can be provided in two ways:

**Via environment variables / config** (shared across all sessions):

```elixir
# config/runtime.exs
config :zoom_gate,
  zoom_sdk_key: System.get_env("ZOOM_SDK_KEY"),
  zoom_sdk_secret: System.get_env("ZOOM_SDK_SECRET"),
  zoom_zak: System.get_env("ZOOM_ZAK")
```

**Per-request** (overrides config, useful for multi-tenant setups):

```elixir
ZoomGate.join_meeting("123456789",
  sdk_key: "per_request_key",
  sdk_secret: "per_request_secret",
  zak: "per_request_zak"
)
```

Via REST:

```bash
curl -X POST http://localhost:4000/api/sessions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "meeting_id": "123456789",
    "sdk_key": "per_request_key",
    "sdk_secret": "per_request_secret"
  }'
```

If both are provided, per-request values take precedence.

## ZAK Token

The ZAK (Zoom Access Key) token is required to join as host (role=1).
Host or co-host role is required for waiting room management -- regular
participants cannot see or control the waiting room.

### Obtaining a ZAK

Fetch it via the Zoom OAuth API:

```
GET https://api.zoom.us/v2/users/me/zak
Authorization: Bearer <oauth_access_token>
```

Response:

```json
{"token": "eyJ0eXAiOiJKV1QiLCJzdiI6..."}
```

### ZAK Expiration

ZAK tokens expire after approximately **1 hour**. Key behaviors:

- **Before joining**: If the ZAK is expired when `join_meeting/2` is called,
  the join will fail with a Zoom SDK error (`JOIN_MEETING_FAILED`, errorCode 200).
- **During a session**: If the ZAK expires while a session is active, the
  session **continues to work** because authentication has already completed
  with the RWG server.
- **Best practice**: Refresh the ZAK token via OAuth immediately before each
  `join_meeting/2` call. Do not cache ZAK tokens for extended periods.

### Role Selection

The Session automatically selects the role based on whether a ZAK is provided:

| ZAK Provided | Role | Capabilities |
|-------------|------|-------------|
| Yes | `1` (host) | Full waiting room control, admit/deny/expel/mute |
| No | `0` (participant) | Join only, no waiting room visibility |

## Production Recommendations

1. **Always set `ZOOM_GATE_API_KEY`** in production. Without it, anyone who
   can reach the service can control meetings.

2. **Use HTTPS**. Deploy ZoomGate behind a reverse proxy (nginx, Caddy, or a
   cloud load balancer) with TLS termination. ZoomGate itself serves plain HTTP.

3. **Never expose SDK secrets to clients**. The `sdk_secret` is used server-side
   to sign JWTs. It should never appear in browser code or client-side apps.

4. **Rotate credentials**. If SDK credentials are compromised, regenerate them
   in the Zoom Marketplace dashboard and redeploy.

5. **Protect Erlang distribution**. If running a BEAM cluster, use strong
   distribution cookies (`-setcookie`) and restrict the EPMD/distribution
   ports to trusted networks.

6. **Restrict network access**. In Docker/Kubernetes, ensure only your
   application can reach ZoomGate's port (4000). Use network policies or
   security groups.
