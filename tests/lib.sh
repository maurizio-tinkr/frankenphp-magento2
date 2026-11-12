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

# http_get <path> [curl args...] — sets BODY and HTTP_STATUS (not in a subshell: call it directly)
HTTP_STATUS=000
BODY=
http_get() {
    local path=$1; shift
    local out; out=$(mktemp)
    HTTP_STATUS=$(curl -s -o "$out" -w '%{http_code}' --max-time 120 "$@" "${BASE_URL}${path}")
    BODY=$(cat "$out"); rm -f "$out"
}

# http_status <path> — sets HTTP_STATUS only (for images, CSS)
http_status() {
    HTTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 120 "${BASE_URL}$1")
}

# wait_for_web — the runtime may still be starting after an up/restart
wait_for_web() {
    for _ in $(seq 60); do
        [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${BASE_URL}/")" != 000 ] && return 0
        sleep 1
    done
    fail "nothing answers on ${BASE_URL} after 60s"; exit 1
}

# service_health <service> — prints healthy/unhealthy/starting/missing
service_health() {
    local id; id=$(docker compose ps -q "$1" 2>/dev/null)
    [ -n "$id" ] || { echo missing; return; }
    docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}' "$id"
}

# A cookie jar per "customer". Magento accepts a form key sent both as cookie and as field
# (that is how its full-page cache works), so we pick our own.
new_session() {
    local jar; jar=$(mktemp)
    printf 'localhost\tFALSE\t/\tFALSE\t0\tform_key\t%s\n' "$1" > "$jar"
    echo "$jar"
}

# add_to_cart <jar> <form_key> <product_id>
add_to_cart() {
    http_get "/checkout/cart/add/product/$3/" -b "$1" -c "$1" -X POST \
        --data "form_key=$2&product=$3&qty=1"
}

# cart_count <jar> — what the minicart would show
cart_count() {
    http_get "/customer/section/load/?sections=cart&force_new_section_timestamp=true" -b "$1" -c "$1" \
        -H 'X-Requested-With: XMLHttpRequest'
    php_json '$d["cart"]["summary_count"] ?? 0' <<<"$BODY" 2>/dev/null || echo 0
}

# php_json <expression on $d> — reads JSON on stdin, uses the app container's PHP (no jq needed)
php_json() {
    docker compose exec -T app php -r '$d = json_decode(stream_get_contents(STDIN), true); echo '"$1"';'
}
