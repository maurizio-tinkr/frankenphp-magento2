ARG PHP_VERSION
FROM php:${PHP_VERSION}-fpm-trixie

ARG COMPOSER_VERSION
COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
COPY php/extensions /tmp/extensions
RUN install-php-extensions $(grep -v '^#' /tmp/extensions) @composer-${COMPOSER_VERSION} \
    && rm /tmp/extensions
COPY php/php.ini $PHP_INI_DIR/conf.d/zz-magento.ini

# Run as www-data, like FrankenPHP: drop the pool's user/group, which only apply to a root master.
RUN sed -i '/^user\s*=\|^group\s*=/d' /usr/local/etc/php-fpm.d/www.conf
RUN mkdir -p /composer-cache && chown www-data:www-data /composer-cache
COPY nginx-fpm/www.conf /usr/local/etc/php-fpm.d/zz-magento.conf
WORKDIR /var/www/html
USER www-data
