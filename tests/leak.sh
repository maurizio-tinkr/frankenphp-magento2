#!/usr/bin/env bash
# Three customers (and an admin) use the store at the same time. B must never see A's cart or C's login, and A and C
# must keep theirs. In FrankenPHP worker mode the same PHP process serves both, so this is where
# state left over from one request would show up in the next. Needs SAMPLE_DATA=1.
. "$(dirname "$0")/lib.sh"
wait_for_web
ROUNDS=${ROUNDS:-50}

"$(dirname "$0")/smoke.sh" >/dev/null 2>&1 && pass "smoke test passes" || fail "smoke test fails"

# A: a guest filling a cart. C: a logged-in customer. B: a guest who must see neither.
# Every round someone also opens the admin, which changes PHP's session settings in the worker it lands on.
# Form keys are random so every run starts with fresh guest carts.
ka=leakA$RANDOM$RANDOM$RANDOM kb=leakB$RANDOM$RANDOM$RANDOM kc=leakC$RANDOM$RANDOM$RANDOM
a=$(new_session "$ka"); b=$(new_session "$kb"); c=$(new_session "$kc")
trap 'rm -f "$a" "$b" "$c"' EXIT

login "$c" "$kc" roni_cost@example.com 'roni_cost3@example.com'
name_c=$(section "$c" customer | php_json '$d["customer"]["fullname"] ?? ""')
[ "$name_c" = "Veronica Costello" ] && pass "C is logged in as $name_c" || fail "C could not log in (got '${name_c}')"

cart_leaks=0 login_leaks=0 a_lost=0 c_lost=0 errors=0
for i in $(seq "$ROUNDS"); do
    http_get /admin/
    add_to_cart "$a" "$ka" 1
    [ "$HTTP_STATUS" = 302 ] || errors=$((errors + 1))
    nb=$(cart_count "$b")
    [ "${nb:-0}" = 0 ] || cart_leaks=$((cart_leaks + 1))
    who=$(section "$b" customer | php_json '$d["customer"]["fullname"] ?? ""')
    [ -z "$who" ] || login_leaks=$((login_leaks + 1))
    na=$(cart_count "$a")
    [ "${na:-0}" = "$i" ] || { a_lost=$((a_lost + 1)); [ $a_lost -le 3 ] && echo "   round $i: A's cart shows ${na:-nothing}" >&2; }
    who=$(section "$c" customer | php_json '$d["customer"]["fullname"] ?? ""')
    [ "$who" = "Veronica Costello" ] || { c_lost=$((c_lost + 1)); [ $c_lost -le 3 ] && echo "   round $i: C is '${who}'" >&2; }
done

[ $errors = 0 ] && pass "no failed requests" || fail "$errors requests failed"
[ $cart_leaks = 0 ] && pass "B never saw A's cart ($ROUNDS rounds)" || fail "B saw A's cart in $cart_leaks of $ROUNDS rounds"
[ $login_leaks = 0 ] && pass "B never saw C's login ($ROUNDS rounds)" || fail "B saw C's login in $login_leaks of $ROUNDS rounds"
[ $a_lost = 0 ] && pass "A's cart counted exactly 1..$ROUNDS" || fail "A's cart count was wrong in $a_lost of $ROUNDS rounds"
[ $c_lost = 0 ] && pass "C stayed logged in ($ROUNDS rounds)" || fail "C was logged out in $c_lost of $ROUNDS rounds"

done_or_fail
