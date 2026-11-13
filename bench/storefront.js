// Storefront load test. Run it with the command in the README, for example:
//   docker compose --profile bench run --rm k6 run -e SCENARIO=category -e LABEL=frankenphp-worker-fpc-on /bench/storefront.js
//
// SCENARIO: home | category | product | search | cart
// LABEL:    names the result file in bench/results/ (runtime, mode, cache state)
// Load:     VUS virtual users (default 16) for DURATION (default 30s), after a 10s warm-up that is not counted.
import http from 'k6/http';
import { check } from 'k6';

const TARGET = __ENV.TARGET || 'http://backend';      // the runtime's web entry point, inside the compose network
const HOST = __ENV.HOST || 'localhost:8080';           // the store's base URL host, so Magento does not redirect
const SCENARIO = __ENV.SCENARIO || 'home';
const LABEL = __ENV.LABEL || 'run';
const VUS = parseInt(__ENV.VUS || '16', 10);
const DURATION = __ENV.DURATION || '30s';

const PAGES = {
    home: ['/'],
    category: [
        '/gear/bags.html',
        '/gear/fitness-equipment.html',
        '/women/tops-women/jackets-women.html',
        '/men/tops-men/hoodies-and-sweatshirts-men.html',
    ],
    product: [
        '/joust-duffle-bag.html',
        '/strive-shoulder-pack.html',
        '/push-it-messenger-bag.html',
        '/overnight-duffle.html',
    ],
    search: ['bag', 'jacket', 'yoga', 'shirt', 'pants'].map((q) => `/catalogsearch/result/?q=${q}`),
};

if (!PAGES[SCENARIO] && SCENARIO !== 'cart') {
    throw new Error(`Unknown SCENARIO "${SCENARIO}": use home, category, product, search or cart`);
}

export const options = {
    scenarios: {
        warmup: { executor: 'constant-vus', vus: VUS, duration: '10s', gracefulStop: '5s' },
        measure: { executor: 'constant-vus', vus: VUS, duration: DURATION, startTime: '15s' },
    },
    thresholds: {
        // A broken runtime must not produce good-looking numbers.
        'http_req_failed{scenario:measure}': ['rate<0.01'],
        'http_req_duration{scenario:measure}': ['p(95)<60000'],
        'http_reqs{scenario:measure}': ['count>0'],
        'checks{scenario:measure}': ['rate>0.99'],
    },
    summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

const params = { headers: { Host: HOST }, redirects: 0 };

export default function () {
    if (SCENARIO === 'cart') {
        // A new guest every iteration (k6 empties the cookie jar between iterations): first add to cart.
        const formKey = `k6${__VU}x${__ITER}`.padEnd(16, '0').slice(0, 16);
        http.cookieJar().set(TARGET, 'form_key', formKey);
        const res = http.post(`${TARGET}/checkout/cart/add/product/1/`, { form_key: formKey, product: '1', qty: '1' }, params);
        check(res, { 'added (302)': (r) => r.status === 302 });
        return;
    }
    const pages = PAGES[SCENARIO];
    const res = http.get(`${TARGET}${pages[(__VU + __ITER) % pages.length]}`, params);
    check(res, { 'status 200': (r) => r.status === 200, 'is a page': (r) => (r.body || '').includes('</html>') });
}

export function handleSummary(data) {
    const m = (name) => data.metrics[name] && data.metrics[name].values;
    const reqs = m('http_reqs{scenario:measure}');
    const dur = m('http_req_duration{scenario:measure}');
    const failed = m('http_req_failed{scenario:measure}');
    const seconds = parseFloat(DURATION) || 30;
    const line = reqs && dur
        ? `${LABEL} ${SCENARIO}: ${(reqs.count / seconds).toFixed(1)} req/s, median ${dur.med.toFixed(1)} ms, p95 ${dur['p(95)'].toFixed(1)} ms, failed ${(failed.rate * 100).toFixed(2)}%\n`
        : `${LABEL} ${SCENARIO}: no measurements\n`;
    const stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-');
    return {
        stdout: line,
        [`/bench/results/${LABEL}-${SCENARIO}-${stamp}.json`]: JSON.stringify({ label: LABEL, scenario: SCENARIO, vus: VUS, duration: DURATION, metrics: data.metrics }, null, 2),
    };
}
