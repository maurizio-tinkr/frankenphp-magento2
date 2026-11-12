#!/usr/bin/env bash
# Each extra in COMPOSE_PROFILES runs and Magento uses it. Needs an installed store with the extras wired in
# (by the installer, or by the commands in the README).
. "$(dirname "$0")/lib.sh"
wait_for_web

has() { [[ ",${COMPOSE_PROFILES}," == *",$1,"* ]]; }
magento() { docker compose exec -T app bin/magento "$@" 2>&1; }
[ -n "${COMPOSE_PROFILES}" ] || { echo "⏩ no profiles enabled"; exit 0; }

if has rabbitmq; then
    [ "$(service_health rabbitmq)" = healthy ] && pass "rabbitmq healthy" || fail "rabbitmq is $(service_health rabbitmq)"
    q=$(docker compose exec -T rabbitmq rabbitmqctl list_queues -q name 2>/dev/null | grep -c .)
    [ "${q:-0}" -gt 0 ] && pass "Magento declared $q queues in RabbitMQ" || fail "no Magento queues in RabbitMQ: AMQP not wired"
    c=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${RABBITMQ_UI_PORT}/")
    [ "$c" = 200 ] && pass "RabbitMQ UI on :${RABBITMQ_UI_PORT}" || fail "RabbitMQ UI: HTTP $c"
fi

if has mailpit; then
    email="profiles-$(date +%s)@example.com"
    jar=$(new_session profilesFormKey1)
    http_get /customer/account/createpost/ -b "$jar" -c "$jar" -X POST \
        --data-urlencode form_key=profilesFormKey1 --data-urlencode firstname=Mail --data-urlencode lastname=Test \
        --data-urlencode "email=$email" --data-urlencode password='Passw0rd!Long' \
        --data-urlencode password_confirmation='Passw0rd!Long'
    rm -f "$jar"
    found=0
    for _ in $(seq 20); do
        curl -s "http://localhost:${MAILPIT_UI_PORT}/api/v1/search?query=to:$email" | grep -q '"messages_count":[1-9]' \
            && { found=1; break; }
        sleep 1
    done
    [ $found = 1 ] && pass "welcome mail for $email reached Mailpit" || fail "no mail for $email in Mailpit"
fi

if has opensearch-dashboards; then
    c=000
    for _ in $(seq 60); do
        c=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${OPENSEARCH_DASHBOARDS_PORT}/api/status")
        [ "$c" = 200 ] && break; sleep 2
    done
    [ "$c" = 200 ] && pass "OpenSearch Dashboards on :${OPENSEARCH_DASHBOARDS_PORT}" || fail "OpenSearch Dashboards: HTTP $c"
fi

if has varnish; then
    [ "$(magento config:show system/full_page_cache/caching_application | tr -d '\r')" = 2 ] \
        && pass "Magento uses Varnish for full-page cache" || fail "Magento's full-page cache is not Varnish"
    hits() { docker compose exec -T varnish varnishstat -1 -f MAIN.cache_hit | awk '{print $2}'; }
    h1=$(hits); http_get /gear/bags.html; http_get /gear/bags.html; h2=$(hits)
    [ "${h2:-0}" -gt "${h1:-0}" ] 2>/dev/null && pass "Varnish served a cached page on :${HTTP_PORT}" \
        || fail "no Varnish cache hit on :${HTTP_PORT} (hits ${h1:-?} → ${h2:-?})"
    magento cache:clean full_page >/dev/null
    out=$(magento cache:flush full_page)
    grep -qi 'error\|exception' <<<"$out" && fail "purging Varnish failed: $out" || pass "Magento purges Varnish"
fi

done_or_fail
