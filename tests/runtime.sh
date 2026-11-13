#!/usr/bin/env bash
# The PHP runtime in COMPOSE_FILE is built as .env and php/ say, and serves HTTP.
. "$(dirname "$0")/lib.sh"

# Required by Magento / Mage-OS (system requirements page) plus php/extensions.
required="bcmath ctype curl dom fileinfo gd hash iconv intl json libxml mbstring openssl pcntl pcre pdo_mysql
simplexml soap sockets sodium xml xsl zip zlib $(grep -v '^#' php/extensions 2>/dev/null)"

mods=$(docker compose exec -T app php -m 2>/dev/null | tr 'A-Z' 'a-z' | tr -d '\r')
[ -n "$mods" ] || fail "app container not running or has no php"
for e in $required; do
    grep -qx "$(echo "$e" | tr 'A-Z' 'a-z')" <<<"$mods" || fail "extension missing: $e"
done
[ "$FAILED" = 0 ] && pass "all $(wc -w <<<"$required" | tr -d ' ') extensions loaded"

v=$(docker compose exec -T app php -r 'echo PHP_VERSION;' 2>/dev/null)
[[ "$v" == "${PHP_VERSION}"* ]] && pass "PHP $v" || fail "PHP version: expected ${PHP_VERSION}, got ${v:-nothing}"

ini=$(docker compose exec -T app php -i 2>/dev/null)
grep -q '^opcache.enable => On' <<<"$ini" && pass "OPcache on" || fail "OPcache is off"
grep -q '^memory_limit => 2G' <<<"$ini" && pass "memory_limit 2G from php/php.ini" || fail "php/php.ini not loaded"

u=$(docker compose exec -T app sh -c 'ps -o user= -p 1 2>/dev/null || stat -c %U /proc/1' | tr -d '\r ')
[ "$u" = www-data ] && pass "app runs as www-data" || fail "app runs as ${u:-unknown}, expected www-data"

http_get /
[ "$HTTP_STATUS" != 000 ] && pass "web answers on :${HTTP_PORT} (HTTP $HTTP_STATUS)" || fail "nothing answers on :${HTTP_PORT}"

# FrankenPHP worker mode: Magento's pages, the home page included, must be served by the worker.
if [[ "${COMPOSE_FILE}" == *frankenphp* ]]; then
    for path in / /gear/bags.html; do
        h=$(curl -s -D - -o /dev/null "${BASE_URL}${path}" | grep -ci '^x-frankenphp-worker:')
        if [ "${FRANKENPHP_MODE}" = worker ]; then
            [ "$h" = 1 ] && pass "$path served by the worker" || fail "$path not served by the worker"
        else
            [ "$h" = 0 ] && pass "$path served classic" || fail "$path served by a worker in classic mode"
        fi
    done
fi

done_or_fail
