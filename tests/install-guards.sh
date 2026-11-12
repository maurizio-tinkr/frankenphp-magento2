#!/usr/bin/env bash
# The installer refuses what it must refuse. Needs an installed store.
. "$(dirname "$0")/lib.sh"

out=$(docker compose run --rm -T install 2>&1); rc=$?
[ $rc -ne 0 ] && grep -q 'REINSTALL=1' <<<"$out" \
    && pass "second install refused, names REINSTALL=1" || fail "second install: exit $rc, output: $(tail -2 <<<"$out")"

start=$(date +%s)
out=$(docker compose run --rm -T -e MAGENTO_DISTRIBUTION=magento -e MAGENTO_COMPOSER_PUBLIC_KEY= \
    -e MAGENTO_COMPOSER_PRIVATE_KEY= install 2>&1); rc=$?
took=$(( $(date +%s) - start ))
[ $rc -ne 0 ] && grep -q MAGENTO_COMPOSER_PUBLIC_KEY <<<"$out" && grep -q MAGENTO_COMPOSER_PRIVATE_KEY <<<"$out" \
    && pass "magento without keys refused (${took}s)" || fail "magento without keys: exit $rc, output: $(tail -2 <<<"$out")"
[ "$took" -le 30 ] || fail "keys check took ${took}s, should fail before anything slow"

curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/" | grep -q 200 && pass "store still up" || fail "store broken by the guards"

done_or_fail
