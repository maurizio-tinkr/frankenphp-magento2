#!/usr/bin/env bash
# The store works: storefront pages, search, cart, admin.
. "$(dirname "$0")/lib.sh"
wait_for_web

http_get /; body=$BODY
[ "$HTTP_STATUS" = 200 ] && pass "home page 200" || fail "home page: HTTP $HTTP_STATUS"

http_get /admin/; body=$BODY
[ "$HTTP_STATUS" = 200 ] && grep -qi 'name="login\[username\]"' <<<"$body" \
    && pass "admin login page" || fail "admin login page: HTTP $HTTP_STATUS"

if [ "${SAMPLE_DATA}" = 1 ]; then
    http_get /gear/bags.html; body=$BODY
    n=$(grep -c 'product-item-info' <<<"$body")
    [ "$HTTP_STATUS" = 200 ] && [ "$n" -gt 0 ] && pass "category page, $n products" \
        || fail "category page: HTTP $HTTP_STATUS, $n products"

    http_get /joust-duffle-bag.html; body=$BODY
    [ "$HTTP_STATUS" = 200 ] && grep -q 'Joust Duffle Bag' <<<"$body" \
        && pass "product page" || fail "product page: HTTP $HTTP_STATUS"

    img=$(grep -o 'http://localhost:[0-9]*/media/catalog/product/cache/[^"]*\.jpg' <<<"$body" | head -1)
    http_status "${img#${BASE_URL}}"
    [ -n "$img" ] && [ "$HTTP_STATUS" = 200 ] && pass "product image" || fail "product image: HTTP $HTTP_STATUS ${img:-not found}"

    css=$(grep -o 'http://localhost:[0-9]*/static/version[^"]*/styles-m.css' <<<"$body" | head -1)
    http_status "${css#${BASE_URL}}"
    [ -n "$css" ] && [ "$HTTP_STATUS" = 200 ] && pass "static CSS" || fail "static CSS: HTTP $HTTP_STATUS ${css:-not found}"

    http_get '/catalogsearch/result/?q=bag'; body=$BODY
    n=$(grep -c 'product-item-info' <<<"$body")
    [ "$HTTP_STATUS" = 200 ] && [ "$n" -gt 0 ] && pass "search, $n results" \
        || fail "search: HTTP $HTTP_STATUS, $n results"

    jar=$(new_session smokeTestFormKey)
    add_to_cart "$jar" smokeTestFormKey 1
    c=$(cart_count "$jar"); rm -f "$jar"
    [ "$c" -ge 1 ] 2>/dev/null && pass "add to cart ($c item)" || fail "add to cart: cart has ${c:-?} items"
fi

done_or_fail
