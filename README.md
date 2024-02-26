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
- `dunglas/frankenphp:1.0.3-php8.3` has to be used to resolve https://github.com/dunglas/frankenphp/issues/567
- I doubt `mailhog` will be connected as the sendmail configuration is missing. See [this](https://github.com/ityetti/magento2-docker/blob/master/php-fpm/Dockerfile) for more info.
- It would be nice to switch from MySQL to MariaDB

## Useful rescources

- [svenakela/caddy-based-magento](https://github.com/svenakela/caddy-based-magento) - A collection of Docker images for running Magento 2 through Caddy Server v2.
- [ityetti/magento2-docker](https://github.com/ityetti/magento2-docker) - Magento 2 Docker to Development (For Apple Silicon)