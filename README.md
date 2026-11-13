# FrankenPHP + Magento 2

Magento 2 (Mage-OS by default) running on [FrankenPHP](https://frankenphp.dev), in classic mode and in worker mode, with nginx + php-fpm next to it so you can compare the 3.

I started this in 2023 as a quick proof of concept. It got stuck on FrankenPHP 1.0.3 (a Go pointer panic), half the services never worked, and it sat there for 3 years. I finally finished it.

It's a PoC. I built it because I wanted to see if it could be done. Don't run your shop on it.

## What's in it

Everything is plain Docker Compose, configured from one `.env` file. Every command you need is in this README, written out in full.

| Service | Default | Notes |
|---|---|---|
| Magento | Mage-OS 4.0.0 (Magento 2.4.9) | Magento Open Source works too, with your own keys |
| PHP | 8.5.12 | the same patch version in FrankenPHP and php-fpm |
| FrankenPHP | 1.13.5 | `classic` or `worker` mode |
| nginx + php-fpm | nginx 1.28 | for the comparison |
| Database | MariaDB 12.3 | or MySQL 8.4 |
| Search | OpenSearch 3.9.0 | |
| Cache and sessions | Valkey 8.0 | |
| RabbitMQ | 4.1 | optional |
| Varnish | 7.7 | optional |
| Mailpit | 1.33.1 | optional |
| OpenSearch Dashboards | 3.9.0 | optional |
| k6 | 2.4.0 | for the benchmark |

The versions are the recommended ones from the [Mage-OS system requirements](https://mage-os.org/get-started/system-requirements). Every image is official and multi-arch, so it runs on Intel and ARM (Apple Silicon included) without changes.

## Requirements

- Docker with Compose 2.24 or newer (OrbStack, Docker Desktop or plain Docker Engine on Linux)
- About 8 GB of RAM for Docker
- Ports 8080 and 3306 free on your machine (or change them in `.env`)

## Quick start

```shell
git clone https://github.com/maurizio-tinkr/frankenphp-magento2.git
cd frankenphp-magento2
cp .env.example .env

docker compose up -d --wait
docker compose run --rm install
docker compose restart app
```

The install downloads Mage-OS with the sample data (the Luma demo store), installs it and switches it to production mode. It took 3 minutes on my machine, longer the first time while the images download.

Then open:

- Store: http://localhost:8080/
- Admin: http://localhost:8080/admin (`admin` / `Admin123!`)

The `restart` matters: OPcache doesn't check files for changes (production settings), so the running app only sees the new code after a restart.

Running the install twice won't wipe your store. It stops and tells you how to start over:

```shell
docker compose run --rm -e REINSTALL=1 install
docker compose restart app
```

## Configuration

Everything lives in `.env`. The file is commented, but these are the switches you'll actually touch.

### Runtime and mode

```shell
# FrankenPHP (default)
COMPOSE_FILE=compose.yml:compose.frankenphp.yml

# nginx + php-fpm
COMPOSE_FILE=compose.yml:compose.nginx-fpm.yml

# FrankenPHP only: classic (default) or worker
FRANKENPHP_MODE=classic
```

`COMPOSE_FILE` is Compose's own variable, so a plain `docker compose` picks the right files up. After changing either setting:

```shell
docker compose up -d --wait --remove-orphans
docker compose restart app
```

The Magento code lives in a Docker volume shared by all runtimes, so switching never reinstalls anything.

### Database

```shell
DB_ENGINE=mariadb   # or mysql
DB_VERSION=12.3     # 8.4 for mysql
```

Each engine keeps its data in its own volume, so switching engine means a fresh store:

```shell
docker compose up -d --wait --remove-orphans
docker compose run --rm -e REINSTALL=1 install
docker compose restart app
```

### Magento Open Source instead of Mage-OS

Mage-OS installs without any account. For Adobe's Magento you need [access keys](https://commercemarketplace.adobe.com/customer/accessKeys/):

```shell
MAGENTO_DISTRIBUTION=magento
MAGENTO_VERSION=2.4.9
MAGENTO_COMPOSER_PUBLIC_KEY=your-public-key
MAGENTO_COMPOSER_PRIVATE_KEY=your-private-key
```

Adobe's [requirements for 2.4.9](https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/system-requirements) differ from Mage-OS's in a few places. If you want to match them: `VALKEY_VERSION=9`, `RABBITMQ_VERSION=4.3`, `VARNISH_VERSION=8`, `NGINX_VERSION=1.30`.

### Resources

```shell
PHP_WORKERS=8    # php-fpm children = FrankenPHP threads = FrankenPHP workers
APP_CPUS=4       # CPU limit of the app container, whatever the runtime
APP_MEMORY=4g
```

These are the same for every runtime, so the comparison stays fair.

## Extras

RabbitMQ, Mailpit, OpenSearch Dashboards and Varnish are off by default. Turn them on with Compose's own `COMPOSE_PROFILES`:

```shell
COMPOSE_PROFILES=rabbitmq,mailpit,opensearch-dashboards,varnish
```

Varnish takes over port 8080 (so the store URL doesn't change), and the runtime moves out of its way. Uncomment this line too:

```shell
WEB_PORT=8081
```

If you turn the extras on **before** installing, the installer wires them into Magento. If the store is already installed, start them and wire them in by hand:

```shell
docker compose up -d --wait --remove-orphans

# RabbitMQ
docker compose exec app bin/magento setup:config:set --no-interaction \
    --amqp-host=rabbitmq --amqp-port=5672 --amqp-user=magento --amqp-password=magento
docker compose exec app bin/magento setup:upgrade --keep-generated

# Mailpit
docker compose exec app bin/magento config:set --lock-env system/smtp/disable 0
docker compose exec app bin/magento config:set --lock-env system/smtp/transport smtp
docker compose exec app bin/magento config:set --lock-env system/smtp/host mailpit
docker compose exec app bin/magento config:set --lock-env system/smtp/port 1025

# Varnish
docker compose exec app bin/magento config:set --lock-env system/full_page_cache/caching_application 2
docker compose exec app bin/magento setup:config:set --no-interaction --http-cache-hosts=varnish:80

docker compose exec app bin/magento cache:flush
docker compose restart app
```

| Extra | URL |
|---|---|
| RabbitMQ | http://localhost:15672 (`magento` / `magento`) |
| Mailpit | http://localhost:8025 |
| OpenSearch Dashboards | http://localhost:5601 |

Turning an extra off again is a reinstall (`docker compose run --rm -e REINSTALL=1 install`). I didn't write the commands to unwire them.

The Varnish config in `varnish/default.vcl` comes from `bin/magento varnish:vcl:generate`. On Mage-OS 4.0.0 the generator left its template placeholders empty, so I filled them in by hand (the comment at the top says which ones).

## Worker mode

This is the interesting part, and the reason the repo exists.

In classic mode, every request boots Magento from scratch, same as php-fpm. In worker mode, FrankenPHP keeps a PHP script running and hands it one request after another, so you only pay for the boot once.

Magento was never built for that. It assumes every request starts with a clean process, and it keeps plenty of state around: the request, the response, the session, the layout, the registry, the app area. Magento has some code to reset that state between requests (`ResetAfterRequestInterface`), but it was written for Adobe's GraphQL application server, and nothing in Magento Open Source or Mage-OS hooks it up.

So [`frankenphp/worker.php`](frankenphp/worker.php) does something blunter. It keeps PHP's loaded classes, the DI configuration and the connections to the database and Valkey, and builds a **brand-new ObjectManager for every request**. No Magento object survives from one request to the next, so there's nothing for one customer's data to hide in.

It didn't work on the first try. These are the bugs I hit, all found by the tests in `tests/` or by the benchmark:

- **Area code is already set.** Reusing one ObjectManager breaks on the second request. That's why every request gets a new one.
- **Too many connections.** A new ObjectManager means a new database connection per request, and MariaDB ran out after about 150. The database and cache connections are now shared.
- **1.7 MB leaked per request.** Every new ObjectManager registers one more code-generation autoloader, which holds on to it forever. 1,000 requests and the container hit its 4 GB limit. The worker now removes the autoloaders a request added.
- **Sessions never saved.** Magento saves sessions in a shutdown function, which in worker mode only runs when the worker stops. The worker saves the session itself at the end of each request (and empties the session objects that the shutdown functions keep alive).
- **4.9 MB leaked per add to cart.** Magento keeps 2 lists in static properties that it never empties (`Config\Base::$instances` and the commit callbacks in `CallbackPool`). In classic mode the process ends and takes them along. In worker mode the cart benchmark ran the container out of memory in under a minute. The worker now empties both after each request.
- **Opening the admin broke the next customer's cart.** The admin renames the PHP session cookie with `ini_set()`, and in worker mode that sticks. Customers who landed on the same worker afterwards got a fresh empty session. The worker now restores every PHP setting before each request (it has to be before: once a response is out, PHP refuses to touch the session settings).

Where it stands now:

- The store works in worker mode: home, categories, products, search, cart, customer login, admin.
- `tests/leak.sh` runs 3 customers and an admin side by side, 100 rounds, on 8 workers that restart along the way. Nobody sees anybody else's cart or login, and nobody loses their own.
- Memory stays flat: `tests/memory.sh` sends 1,000 page views and adds to cart, and the app container grows by less than 50 MB (it grew by 2 GB before the last fix).
- Each worker still restarts after 500 requests (`WORKER_MAX_REQUESTS`), as a safety net.

What I can't promise: static properties are **not** reset between requests. Any Magento module (or third-party extension) that keeps customer data in a static property will leak it in worker mode. The tests cover the core storefront flows above and nothing else. Checkout, payments, multi-store, B2B: not tested.

It passes everything I threw at it. I still wouldn't put it in front of real customers.

## Benchmark

k6 runs inside the Compose network and hits the runtime directly (Varnish isn't involved, even when it's on). Each run is a 10 second warm-up, which isn't counted, then 30 seconds with 16 virtual users. A run fails if more than 1% of requests fail, so a broken runtime can't post good numbers.

```shell
# SCENARIO: home, category, product, search or cart
# LABEL: whatever you want in the result file name
docker compose --profile bench run --rm k6 run -e SCENARIO=category -e LABEL=frankenphp-worker /bench/storefront.js
```

Results land in `bench/results/`. To measure without Magento's full-page cache, turn it off first (and back on after):

```shell
docker compose exec app bin/magento cache:disable full_page
docker compose restart app
```

```shell
docker compose exec app bin/magento cache:enable full_page
docker compose restart app
```

### Results

Requests per second (median response time). Higher is better.

| Page | Full-page cache | nginx + php-fpm | FrankenPHP classic | FrankenPHP worker |
|---|---|---|---|---|
| Home | on | **364 (33 ms)** | 152 (98 ms) | 242 (66 ms) |
| Category | on | **346 (36 ms)** | 142 (102 ms) | 191 (74 ms) |
| Product | on | **353 (34 ms)** | 143 (100 ms) | 242 (67 ms) |
| Home | off | **105 (157 ms)** | 53 (290 ms) | 83 (183 ms) |
| Category | off | 52 (299 ms) | 30 (532 ms) | **56 (272 ms)** |
| Product | off | **54 (295 ms)** | 27 (588 ms) | 36 (408 ms) |
| Search | never cached | 52 (303 ms) | 28 (548 ms) | **57 (271 ms)** |
| Add to cart | never cached | **120 (126 ms)** | 48 (312 ms) | 101 (136 ms) |

Every run: 16 virtual users, 30 seconds, 0 failed requests. Running the same case twice gives numbers 10 to 20% apart, so don't read much into small differences.

What I read in there:

- **nginx + php-fpm wins.** On my machine it serves cached pages at about 350 requests per second, more than twice FrankenPHP classic and about 1.5 times worker mode.
- **Worker mode helps.** Against FrankenPHP classic it's 1.4 to 1.7 times faster on cached pages, and 1.3 to 2 times faster on uncached ones. On uncached category pages and search it even edges past php-fpm (56 against 52, 57 against 52).
- **One request at a time, the gap is small.** A cached category page takes about 15 ms on php-fpm, 20 ms on FrankenPHP classic and 12 ms in worker mode. Under load it opens up: both containers max out their 4 CPUs, FrankenPHP classic just spends about 2.4 times more CPU per cached page. More CPUs or more threads didn't change that. I don't know yet whether it's the thread-safe PHP build, Go's runtime or Docker on a Mac, and I'd love to see the same benchmark on a Linux box.

### Before you quote these numbers

- **It's my laptop.** An Apple M1 Pro (10 cores, 16 GB) running OrbStack 2.2.5, with k6, the database and OpenSearch on the same machine. Docker on a Mac runs inside a VM. Run it on a Linux server and you'll get different numbers.
- **nginx gets 1 extra CPU.** php-fpm gets `APP_CPUS` like FrankenPHP, but nginx runs in its own container with 1 CPU on top. FrankenPHP's web server shares `APP_CPUS` with PHP. That favours nginx + php-fpm a little.
- **The PHP builds differ.** FrankenPHP needs thread-safe PHP (ZTS) and php-fpm uses the standard build (NTS). Same version, same extensions, same `php.ini` (I took the `PHP_VALUE` overrides out of Magento's nginx config so php-fpm really runs on it too), but not the same binary.
- **16 users, 30 seconds.** Enough to compare the 3 runtimes. It doesn't tell you what any of them can sustain in production.

## Tests

Plain bash and curl, run from the repository root against the running stack:

| Script | Checks |
|---|---|
| `tests/base.sh` | database, OpenSearch and Valkey are healthy and at the versions in `.env` |
| `tests/runtime.sh` | the PHP runtime has the right version, extensions and `php.ini`, and runs as `www-data` |
| `tests/smoke.sh` | home, admin, category, product, images, CSS, search, add to cart |
| `tests/install-guards.sh` | a second install is refused; Magento without keys is refused |
| `tests/switch.sh` | switching runtime keeps the store working, and the store works on both database engines. It reinstalls the store twice, so anything you changed in it is gone (takes ~10 minutes) |
| `tests/profiles.sh` | each enabled extra runs and Magento uses it |
| `tests/leak.sh` | customers never see each other's cart or login (`ROUNDS=100 tests/leak.sh`) |
| `tests/memory.sh` | memory doesn't grow under load (the one that matters in worker mode) |

## Stopping and cleaning up

```shell
# stop everything, keep the store
docker compose down

# remove the store, the database and the Composer cache
docker compose --profile install down -v
```

`down -v` only removes the volumes your current `.env` uses. If you switched database engine at some point, the other engine's volume is still there: `docker volume ls` shows it, `docker volume rm` removes it.

## Credits

- [FrankenPHP](https://frankenphp.dev) by Kévin Dunglas and the PHP Foundation
- [Mage-OS](https://mage-os.org)
- [svenakela/caddy-based-magento](https://github.com/svenakela/caddy-based-magento), Magento on Caddy, which helped with the Caddyfile
- [ityetti/magento2-docker](https://github.com/ityetti/magento2-docker), where the 2023 version started
