# [WIP] FrankenPHP + Magento 2

A POC to run Magento 2 using [FrankenPHP](https://github.com/dunglas/frankenphp).

The docker stack includes:

- FrankenPHP - dunglas/frankenphp:latest-php8.2
- MySQL - arm64v8/mysql:8.0.34
- OpenSearch - opensearchproject/opensearch:2.5.0
- OpenSearch dashboard - opensearchproject/opensearch-dashboards:2.5.0
- Redis - arm64v8/redis:7.0
- RabbitMQ - arm64v8/rabbitmq:3.11-management
- MailHog - mailhog/mailhog

## Usage

To build and run the stack simply run:

```shell
docker-compose up -d --build
```
To open an interactive console within the PHP container:

```shell
docker exec -it frankenphp-magento2-php-1 bash
```

The Magento 2 files are expected in `./src`. To install Magento from scratch is as follow:

```shell
 ## Install Application
 bin/magento setup:install \
     --backend-frontname=backend \
     --amqp-host=rabbitmq \
     --amqp-port=5672 \
     --amqp-user=admin \
     --amqp-password=admin \
     --db-host=mysql \
     --db-name=magento \
     --db-user=magento \
     --db-password=magento \
     --search-engine=opensearch \
     --opensearch-host=opensearch \
     --opensearch-port=9200 \
     --opensearch-index-prefix=magento2 \
     --opensearch-enable-auth=0 \
     --opensearch-timeout=15 \
     --session-save=redis \
     --session-save-redis-host=redis \
     --session-save-redis-port=6379 \
     --session-save-redis-db=2 \
     --session-save-redis-max-concurrency=20 \
     --cache-backend=redis \
     --cache-backend-redis-server=redis \
     --cache-backend-redis-db=0 \
     --cache-backend-redis-port=6379 \
     --page-cache=redis \
     --page-cache-redis-server=redis \
     --page-cache-redis-db=1 \
     --page-cache-redis-port=6379

 ## Configure Application
 bin/magento config:set --lock-env web/unsecure/base_url "https://localhost/"

 bin/magento config:set --lock-env web/secure/base_url "https://localhost/"

 bin/magento config:set --lock-env web/secure/offloader_header X-Forwarded-Proto

 bin/magento config:set --lock-env web/secure/use_in_frontend 1
 bin/magento config:set --lock-env web/secure/use_in_adminhtml 1
 bin/magento config:set --lock-env web/seo/use_rewrites 1

 bin/magento config:set --lock-env system/full_page_cache/caching_application 2
 bin/magento config:set --lock-env system/full_page_cache/ttl 604800

 bin/magento config:set --lock-env catalog/search/enable_eav_indexer 1

 bin/magento config:set --lock-env dev/static/sign 0

 bin/magento deploy:mode:set -s developer
 bin/magento cache:disable block_html full_page

 bin/magento indexer:reindex
 bin/magento cache:flush
```

## Issues

- `frankenphp/Dockerfile` is a mess, I copied pasted what I could find online trying to resolve some issues, it will need major refactoring.
- trying to connect to Magento on `https://localhost` results in a `ERR_CONNECTION_CLOSED` with the following being logged by the FrankenPHP container
```shell
2024-02-26 15:45:24 panic: runtime error: runtime.Pinner.Pin: argument is not a Go pointer
2024-02-26 15:45:24 
2024-02-26 15:45:24 goroutine 114 [running, locked to thread]:
2024-02-26 15:45:24 github.com/dunglas/frankenphp.go_apache_request_headers(0x16e8fc0?)
2024-02-26 15:45:24     /go/src/app/frankenphp.go:595 +0x15c
2024-02-26 15:45:24 github.com/dunglas/frankenphp._Cfunc_frankenphp_execute_script(0xfffef41110f0)
2024-02-26 15:45:24     _cgo_gotypes.go:790 +0x34
2024-02-26 15:45:24 github.com/dunglas/frankenphp.go_execute_script(0x40002d9e01?)
2024-02-26 15:45:24     /go/src/app/frankenphp.go:510 +0x11c
2024-02-26 15:45:24 2024/02/26 15:45:24.704     INFO    using provided configuration    {"config_file": "/etc/caddy/Caddyfile", "config_adapter": "caddyfile"}
2024-02-26 15:45:24 2024/02/26 15:45:24.706     WARN    Caddyfile input is not formatted; run 'caddy fmt --overwrite' to fix inconsistencies    {"adapter": "caddyfile", "file": "/etc/caddy/Caddyfile", "line": 2}
2024-02-26 15:45:24 2024/02/26 15:45:24.707     INFO    admin   admin endpoint started  {"address": "localhost:2019", "enforce_origin": false, "origins": ["//[::1]:2019", "//127.0.0.1:2019", "//localhost:2019"]}
2024-02-26 15:45:24 2024/02/26 15:45:24.708     INFO    tls.cache.maintenance   started background certificate maintenance      {"cache": "0x4000359900"}
2024-02-26 15:45:24 2024/02/26 15:45:24.708     INFO    http.auto_https server is listening only on the HTTPS port but has no TLS connection policies; adding one to enable TLS {"server_name": "srv0", "https_port": 443}
2024-02-26 15:45:24 2024/02/26 15:45:24.708     INFO    http.auto_https enabling automatic HTTP->HTTPS redirects        {"server_name": "srv0"}
2024-02-26 15:45:24 2024/02/26 15:45:24.712     INFO    FrankenPHP started 🐘    {"php_version": "8.2.16"}
2024-02-26 15:45:24 2024/02/26 15:45:24.715     WARN    tls     storage cleaning happened too recently; skipping for now        {"storage": "FileStorage:/data/caddy", "instance": "b11c4fce-511a-43e4-96bc-8a94a073a0af", "try_again": "2024/02/27 15:45:24.715", "try_again_in": 86399.999999584}
2024-02-26 15:45:24 2024/02/26 15:45:24.717     INFO    tls     finished cleaning storage units
2024-02-26 15:45:24 2024/02/26 15:45:24.769     INFO    pki.ca.local    root certificate is already trusted by system   {"path": "storage:pki/authorities/local/root.crt"}
2024-02-26 15:45:24 2024/02/26 15:45:24.769     INFO    http    enabling HTTP/3 listener        {"addr": ":443"}
2024-02-26 15:45:24 2024/02/26 15:45:24.770     INFO    failed to sufficiently increase receive buffer size (was: 208 kiB, wanted: 2048 kiB, got: 416 kiB). See https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes for details.
2024-02-26 15:45:24 2024/02/26 15:45:24.770     INFO    http.log        server running  {"name": "srv0", "protocols": ["h1", "h2", "h3"]}
2024-02-26 15:45:24 2024/02/26 15:45:24.770     INFO    http.log        server running  {"name": "remaining_auto_https_redirects", "protocols": ["h1", "h2", "h3"]}
2024-02-26 15:45:24 2024/02/26 15:45:24.770     INFO    http    enabling automatic TLS certificate management   {"domains": ["localhost"]}
2024-02-26 15:45:24 2024/02/26 15:45:24.772     WARN    tls     stapling OCSP   {"error": "no OCSP stapling for [localhost]: no OCSP server specified in certificate", "identifiers": ["localhost"]}
2024-02-26 15:45:24 2024/02/26 15:45:24.773     INFO    autosaved config (load with --resume flag)      {"file": "/config/caddy/autosave.json"}
2024-02-26 15:45:24 2024/02/26 15:45:24.773     INFO    serving initial configuration
```
- I doubt `mailhog` will be connected as the sendmail configuration is missing. See [this](https://github.com/ityetti/magento2-docker/blob/master/php-fpm/Dockerfile) for more info.
- It would be nice to switch from MySQL to MariaDB

## Useful rescources

- [svenakela/caddy-based-magento](https://github.com/svenakela/caddy-based-magento) - A collection of Docker images for running Magento 2 through Caddy Server v2.
- [ityetti/magento2-docker](https://github.com/ityetti/magento2-docker) - Magento 2 Docker to Development (For Apple Silicon)