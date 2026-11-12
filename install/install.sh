#!/usr/bin/env bash
# Installs Mage-OS (or Magento) into the shared code volume. Runs inside the install container:
#   docker compose run --rm install
set -uo pipefail

ROOT=/var/www/html
LOG=/tmp/install.log
: > "$LOG"

step() { printf '%s %s... ' "$1" "$2"; }
ok() { echo "✅"; }
die() { echo "❌ $*" >&2; exit "${2:-1}"; }
# run <emoji> <description> <command...> — one line per step, details only on failure
run() {
    local emoji=$1 what=$2; shift 2
    step "$emoji" "$what"
    if "$@" >>"$LOG" 2>&1; then ok; else
        echo "❌"; echo "--- last lines of the log ---" >&2; tail -40 "$LOG" >&2; exit 1
    fi
}
has_profile() { [[ ",${COMPOSE_PROFILES:-}," == *",$1,"* ]]; }

# --- what to install -------------------------------------------------------
case "${MAGENTO_DISTRIBUTION}" in
    mageos)
        REPO=https://repo.mage-os.org/
        PACKAGE=mage-os/project-community-edition
        NAME="Mage-OS ${MAGENTO_VERSION}" ;;
    magento)
        [ -n "${MAGENTO_COMPOSER_PUBLIC_KEY}" ] && [ -n "${MAGENTO_COMPOSER_PRIVATE_KEY}" ] || die \
            "Magento needs repo.magento.com keys: set MAGENTO_COMPOSER_PUBLIC_KEY and MAGENTO_COMPOSER_PRIVATE_KEY in .env (https://commercemarketplace.adobe.com/customer/accessKeys/), or use MAGENTO_DISTRIBUTION=mageos" 3
        REPO=https://repo.magento.com/
        PACKAGE=magento/project-community-edition
        NAME="Magento Open Source ${MAGENTO_VERSION}"
        export COMPOSER_AUTH="{\"http-basic\":{\"repo.magento.com\":{\"username\":\"${MAGENTO_COMPOSER_PUBLIC_KEY}\",\"password\":\"${MAGENTO_COMPOSER_PRIVATE_KEY}\"}}}" ;;
    *) die "MAGENTO_DISTRIBUTION must be mageos or magento, not '${MAGENTO_DISTRIBUTION}'" 3 ;;
esac

# --- never overwrite a store by accident ------------------------------------
CLEANUP=()
if [ -n "$(ls -A "$ROOT")" ]; then
    if [ "${REINSTALL:-0}" != 1 ]; then
        [ -f "$ROOT/app/etc/env.php" ] && what="A store is already installed" || what="A previous install did not finish"
        die "${what}. To wipe it and install again: docker compose run --rm -e REINSTALL=1 install"
    fi
    run 🧹 "Removing the previous install" find "$ROOT" -mindepth 1 -delete
    CLEANUP=(--cleanup-database)
fi

# --- download ---------------------------------------------------------------
run 📦 "Downloading ${NAME}" composer create-project --no-interaction --no-progress \
    --repository-url="$REPO" "${PACKAGE}=${MAGENTO_VERSION}" "$ROOT"
cd "$ROOT" || exit 1

if [ "${SAMPLE_DATA}" = 1 ]; then
    run 🛍️ "Adding sample data" php -d memory_limit=-1 bin/magento sampledata:deploy --no-interaction
fi

# --- install ----------------------------------------------------------------
AMQP=()
if has_profile rabbitmq; then
    AMQP=(--amqp-host=rabbitmq --amqp-port=5672 --amqp-user=magento --amqp-password=magento)
fi

# Two-factor auth for the admin is off: this is a local demo. Magento ships a second 2FA module, Mage-OS doesn't.
DISABLE=Magento_TwoFactorAuth
ls -d vendor/*/module-admin-adobe-ims-two-factor-auth >/dev/null 2>&1 && DISABLE+=,Magento_AdminAdobeImsTwoFactorAuth

run 🛠️ "Installing ${NAME}" bin/magento setup:install --no-interaction "${CLEANUP[@]}" \
    --base-url="http://localhost:${HTTP_PORT}/" \
    --backend-frontname=admin \
    --admin-user="${ADMIN_USER}" --admin-password="${ADMIN_PASSWORD}" --admin-email="${ADMIN_EMAIL}" \
    --admin-firstname=Admin --admin-lastname=User \
    --language=en_US --currency=USD --timezone=UTC --use-rewrites=1 \
    --db-host=db --db-name="${DB_NAME}" --db-user="${DB_USER}" --db-password="${DB_PASSWORD}" \
    --search-engine=opensearch --opensearch-host=opensearch --opensearch-port=9200 \
    --opensearch-index-prefix=magento2 --opensearch-enable-auth=0 \
    --session-save=valkey --session-save-valkey-host=valkey --session-save-valkey-db=2 \
    --cache-backend=valkey --cache-backend-valkey-server=valkey --cache-backend-valkey-db=0 \
    --page-cache=valkey --page-cache-valkey-server=valkey --page-cache-valkey-db=1 \
    --disable-modules="$DISABLE" \
    "${AMQP[@]}"

# --- extras -----------------------------------------------------------------
if has_profile mailpit; then
    run 📬 "Sending mail to Mailpit" bin/magento config:set --lock-env system/smtp/transport smtp
    run 📬 "Mailpit host" bin/magento config:set --lock-env system/smtp/host mailpit
    run 📬 "Mailpit port" bin/magento config:set --lock-env system/smtp/port 1025
else
    run 📭 "Turning off outgoing mail (no Mailpit)" bin/magento config:set --lock-env system/smtp/disable 1
fi
if has_profile varnish; then
    run 🚀 "Using Varnish as full-page cache" bin/magento config:set --lock-env system/full_page_cache/caching_application 2
    run 🚀 "Varnish purge host" bin/magento setup:config:set --no-interaction --http-cache-hosts=varnish:80
fi

# --- production -------------------------------------------------------------
run 🏭 "Switching to production mode (compile, static content)" bin/magento deploy:mode:set production
run 🔎 "Reindexing" bin/magento indexer:reindex
run 🧽 "Flushing caches" bin/magento cache:flush

echo
echo "✅ ${NAME} installed."
echo "   Restart the web runtime so it picks up the new code: docker compose up -d && docker compose restart app"
echo "   Store: http://localhost:${HTTP_PORT}/   Admin: http://localhost:${HTTP_PORT}/admin (${ADMIN_USER} / ${ADMIN_PASSWORD})"
