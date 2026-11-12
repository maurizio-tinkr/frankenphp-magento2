#!/usr/bin/env bash
# Switching runtime keeps the store; switching database engine works after a reinstall.
# Needs an installed store. Takes ~10 minutes (two reinstalls). Leaves the stack on the .env defaults.
. "$(dirname "$0")/lib.sh"
here=$(dirname "$0")

perm_errors() {
    docker compose exec -T app sh -c 'cat var/log/*.log 2>/dev/null | grep -ci "permission denied"' | tr -d '\r'
}

runtime() {  # runtime <compose-file>
    export COMPOSE_FILE="compose.yml:$1"
    docker compose up -d --wait --remove-orphans >/dev/null 2>&1 || { fail "$1 did not start"; return; }
    docker compose restart app >/dev/null 2>&1
    "$here/smoke.sh" >/dev/null 2>&1 && pass "store works on $1" || fail "store broken on $1 (run tests/smoke.sh with COMPOSE_FILE=$COMPOSE_FILE)"
    n=$(perm_errors); [ "${n:-0}" = 0 ] && pass "no permission errors on $1" || fail "$n permission errors in var/log on $1"
}

reinstall_on() {  # reinstall_on <engine> <version>
    export DB_ENGINE=$1 DB_VERSION=$2
    docker compose up -d --wait db >/dev/null 2>&1 || { fail "$1 $2 did not start"; return; }
    docker compose run --rm -T -e REINSTALL=1 install >/dev/null 2>&1 || { fail "install on $1 $2 failed"; return; }
    docker compose up -d --wait >/dev/null 2>&1; docker compose restart app >/dev/null 2>&1
    "$here/smoke.sh" >/dev/null 2>&1 && pass "store works on $1 $2" || fail "store broken on $1 $2"
}

start_file=${COMPOSE_FILE#compose.yml:}
other=compose.nginx-fpm.yml; [ "$start_file" = compose.nginx-fpm.yml ] && other=compose.frankenphp.yml
runtime "$other"
runtime "$start_file"

start_engine=$DB_ENGINE start_version=$DB_VERSION
reinstall_on mysql 8.4
vols=$(docker volume ls --format '{{.Name}}')
grep -q "${COMPOSE_PROJECT_NAME}_db-mariadb$" <<<"$vols" && grep -q "${COMPOSE_PROJECT_NAME}_db-mysql$" <<<"$vols" \
    && pass "separate data volumes for mariadb and mysql" || fail "expected both db-mariadb and db-mysql volumes"
reinstall_on "$start_engine" "$start_version"

done_or_fail
