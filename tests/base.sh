#!/usr/bin/env bash
# The base services are up, healthy and at the versions .env asks for.
. "$(dirname "$0")/lib.sh"

for s in db opensearch valkey; do
    h=$(service_health "$s")
    [ "$h" = healthy ] && pass "$s healthy" || fail "$s is $h"
done

v=$(docker compose exec -T db sh -c 'mariadb --version 2>/dev/null || mysql --version' 2>/dev/null)
case "$v" in
    *"${DB_VERSION}"*) pass "db is ${DB_ENGINE} ${DB_VERSION}" ;;
    *) fail "db version: expected ${DB_VERSION}, got: ${v:-nothing}" ;;
esac
case "$DB_ENGINE:$v" in
    mariadb:*MariaDB*|mysql:*MySQL*) pass "db engine is ${DB_ENGINE}" ;;
    *) fail "db engine: expected ${DB_ENGINE}, got: ${v:-nothing}" ;;
esac

p=$(docker compose exec -T valkey valkey-cli ping 2>/dev/null | tr -d '\r')
[ "$p" = PONG ] && pass "valkey answers PONG" || fail "valkey ping: ${p:-no answer}"

o=$(docker compose exec -T opensearch curl -s localhost:9200 2>/dev/null | grep -o '"number" *: *"[^"]*"')
case "$o" in
    *"\"${OPENSEARCH_VERSION}"*) pass "opensearch ${OPENSEARCH_VERSION}" ;;
    *) fail "opensearch version: expected ${OPENSEARCH_VERSION}, got: ${o:-nothing}" ;;
esac

docker volume ls --format '{{.Name}}' | grep -q "db-${DB_ENGINE}\$" \
    && pass "data volume db-${DB_ENGINE} exists" || fail "no db-${DB_ENGINE} volume"

done_or_fail
