ARG FRANKENPHP_VERSION
ARG PHP_VERSION
FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION}-trixie

ARG COMPOSER_VERSION
COPY php/extensions /tmp/extensions
RUN install-php-extensions $(grep -v '^#' /tmp/extensions) @composer-${COMPOSER_VERSION} \
    && rm /tmp/extensions
COPY php/php.ini $PHP_INI_DIR/conf.d/zz-magento.ini

# Run as www-data, like php-fpm, and still bind port 80.
RUN setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && mkdir -p /var/www/html /composer-cache \
    && chown -R www-data:www-data /var/www/html /composer-cache /config/caddy /data/caddy

COPY frankenphp/Caddyfile /etc/frankenphp/Caddyfile
WORKDIR /var/www/html
USER www-data
