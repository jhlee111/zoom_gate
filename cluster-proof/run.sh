#!/usr/bin/env bash
# S1 proof: zoom_gate forms a BEAM cluster with a peer over a shared docker
# network (positive), and a cookie mismatch is refused (negative). Dev-only.
# Requires docker + `docker compose` v2. Idempotent: tears down on exit.
set -euo pipefail
cd "$(dirname "$0")"
COMPOSE="docker compose -f docker-compose.yml"

cleanup() { COOKIE_GS=wrong_cookie $COMPOSE down -v >/dev/null 2>&1 || true; }
trap cleanup EXIT

wait_node() { # $1 = service name; polls until the local release answers rpc
  local svc="$1"
  for _ in $(seq 1 60); do
    if $COMPOSE exec -T "$svc" /app/bin/zoom_gate rpc 'IO.puts(:booted)' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "✗ node $svc did not boot"; $COMPOSE logs "$svc" | tail -30; return 1
}

echo "### build (zoom_gate image, OTP 28)"
$COMPOSE build >/dev/null

echo "### POSITIVE — shared cookie → cluster forms"
$COMPOSE up -d
wait_node gs_net
wait_node zoom_gate
$COMPOSE exec -T gs_net /app/bin/zoom_gate rpc "$(cat positive.exs)" | tee /tmp/zg_pos.out
grep -q CLUSTER_PROOF_OK /tmp/zg_pos.out
$COMPOSE down -v >/dev/null

echo "### NEGATIVE — mismatched cookie → no connection"
COOKIE_GS=wrong_cookie $COMPOSE up -d
wait_node gs_net
COOKIE_GS=wrong_cookie $COMPOSE exec -T gs_net /app/bin/zoom_gate rpc "$(cat negative.exs)" | tee /tmp/zg_neg.out
grep -q COOKIE_NEGATIVE_OK /tmp/zg_neg.out

echo "### S1 PROOF PASS"
