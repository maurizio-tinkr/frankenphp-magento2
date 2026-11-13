#!/usr/bin/env bash
# The app's memory doesn't grow under load: 1000 requests (pages and add-to-cart, 8 at a time) may add
# at most MAX_GROWTH_MB (default 300). Worker mode keeps PHP alive, so anything a request leaves
# behind adds up here.
. "$(dirname "$0")/lib.sh"
wait_for_web
MAX_GROWTH_MB=${MAX_GROWTH_MB:-300}

mem_mb() {
    docker stats --no-stream --format '{{.MemUsage}}' "$(docker compose ps -q app)" \
        | awk '{ v = $1; u = v; gsub(/[0-9.]/, "", u); gsub(/[^0-9.]/, "", v); print int(u == "GiB" ? v * 1024 : v) }'
}

# Warm up first: OPcache and the workers' first boot are not leaks.
seq 100 | xargs -P 8 -I{} curl -s -o /dev/null "$BASE_URL/gear/bags.html"
before=$(mem_mb)
seq 500 | xargs -P 8 -I{} curl -s -o /dev/null "$BASE_URL/gear/bags.html"
seq 500 | xargs -P 8 -I{} curl -s -o /dev/null -b form_key=memoryTestKey123 -X POST \
    --data 'form_key=memoryTestKey123&product=1&qty=1' "$BASE_URL/checkout/cart/add/product/1/"
after=$(mem_mb)
growth=$((after - before))

[ "$growth" -le "$MAX_GROWTH_MB" ] && pass "memory ${before} → ${after} MB after 1000 requests (+${growth} MB)" \
    || fail "memory grew ${growth} MB after 1000 requests (${before} → ${after} MB, limit ${MAX_GROWTH_MB})"
done_or_fail
