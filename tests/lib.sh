#!/usr/bin/env bash
# Shared helpers for the test scripts. Run tests from the repository root.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 3
[ -f .env ] || { echo "❌ .env missing: run cp .env.example .env" >&2; exit 3; }
set -a; . ./.env; set +a

BASE_URL="http://localhost:${HTTP_PORT}"
FAILED=0

pass() { echo "✅ $*"; }
fail() { echo "❌ $*" >&2; FAILED=1; }
done_or_fail() { [ "$FAILED" = 0 ] || exit 1; }

# http_get <path> [curl args...] — prints the body, sets HTTP_STATUS
http_get() {
    local path=$1; shift
    local out; out=$(mktemp)
    HTTP_STATUS=$(curl -s -o "$out" -w '%{http_code}' --max-time 60 "$@" "${BASE_URL}${path}")
    cat "$out"; rm -f "$out"
}

# service_health <service> — prints healthy/unhealthy/starting/missing
service_health() {
    local id; id=$(docker compose ps -q "$1" 2>/dev/null)
    [ -n "$id" ] || { echo missing; return; }
    docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}' "$id"
}
