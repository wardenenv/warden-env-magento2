#!/usr/bin/env bash
set -eu
trap '>&2 printf "\n\e[01;31mERROR\033[0m: Command \`%s\` on line $LINENO failed with exit code $?\n" "$BASH_COMMAND"' ERR

function :: {
    echo
    echo "==> [$(date +%H:%M:%S)] $@"
}

## find directory above where this script is located following symlinks if neccessary
readonly BASE_DIR="$(
  cd "$(
    dirname "$(
      (readlink "${BASH_SOURCE[0]}" || echo "${BASH_SOURCE[0]}") \
        | sed -e "s#^../#$(dirname "$(dirname "${BASH_SOURCE[0]}")")/#"
    )"
  )/.." >/dev/null \
  && pwd
)"
cd "${BASE_DIR}"

## load configuration needed for setup
REQUIRED_FILES=("webroot/auth.json")
source .env
DB_DUMP="${DB_DUMP:-/tmp/magento-db.sql.gz}"
DB_IMPORT=1
CLEAN_INSTALL=
URL_FRONT="https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
URL_ADMIN="https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/backend/"

## argument parsing
## parse arguments
while (( "$#" )); do
    case "$1" in
        --clean-install)
            CLEAN_INSTALL=1
            DB_IMPORT=
            shift
            ;;
        --skip-db-import)
            DB_IMPORT=
            shift
            ;;
        --db-dump)
            shift
            DB_DUMP="$1"
            shift
            ;;
        --help)
            echo "Usage: $(basename $0) [--skip-db-import] [--db-dump <file>.sql.gz]"
            echo ""
            echo "       --clean-install              install from scratch rather than use existing database dump" 
            echo "       --skip-db-import             skips over db import (assume db has already been imported)"
            echo "       --db-dump <file>.sql.gz      expects path to .sql.gz file for import during init"
            echo ""
            exit -1
            ;;
        *)
            >&2 printf "\e[01;31mERROR\033[0m: Unrecognized argument '$1'\n"
            exit -1
            ;;
    esac
done

## include check for DB_DUMP file only when database import is expected
[[ ${DB_IMPORT} ]] && REQUIRED_FILES+=("${DB_DUMP}" "webroot/app/etc/env.php.warden.php")

:: Verifying configuration
INIT_ERROR=

## check for presence of host machine dependencies
for DEP_NAME in warden mutagen docker-compose pv; do
  if [[ "${DEP_NAME}" = "mutagen" ]] && [[ ! $OSTYPE =~ ^darwin ]]; then
    continue
  fi

  if ! which "${DEP_NAME}" 2>/dev/null >/dev/null; then
    >&2 printf "\e[01;31mERROR\033[0m: Command '${DEP_NAME}' not found. Please install.\n"
    INIT_ERROR=1
  fi
done

## verify warden version constraint
WARDEN_VERSION=$(warden version 2>/dev/null) || true
if ! { \
     (( $(echo ${WARDEN_VERSION:-0} | cut -d. -f1) >= 0 )) \
  && (( $(echo ${WARDEN_VERSION:-0} | cut -d. -f2) >= 2 )) \
  && (( $(echo ${WARDEN_VERSION:-0} | cut -d. -f3) >= 0 )); }
then
  >&2 printf "\e[01;31mERROR\033[0m: Warden 0.2.0 or greater is required (version ${WARDEN_VERSION} is installed)\n"
  INIT_ERROR=1
fi

## copy global Marketplace credentials into webroot to satisfy REQUIRED_FILES list; in ideal
## configuration the per-project auth.json will already exist with project specific keys
if [[ ! -f "webroot/auth.json" ]] && [[ -f ~/.composer/auth.json ]]; then
  if docker run --rm -v ~/.composer/auth.json:/tmp/auth.json \
      composer config -g http-basic.repo.magento.com >/dev/null 2>&1
  then
    >&2 printf "\e[01;31mNOTICE\033[0m: Configuring ./webroot/auth.json with global credentials for repo.magento.com \n"
    echo "{\"http-basic\":{\"repo.magento.com\":$(
      docker run --rm -v ~/.composer/auth.json:/tmp/auth.json composer config -g http-basic.repo.magento.com
    )}}" > ./webroot/auth.json
  fi
fi

## verify mutagen version constraint
MUTAGEN_VERSION=$(mutagen version 2>/dev/null) || true
if [[ $OSTYPE =~ ^darwin ]] && ! { \
     (( $(echo ${MUTAGEN_VERSION:-0} | cut -d. -f1) >= 0 )) \
  && (( $(echo ${MUTAGEN_VERSION:-0} | cut -d. -f2) >= 10 )) \
  && (( $(echo ${MUTAGEN_VERSION:-0} | cut -d. -f3) >= 3 )); }
then
  >&2 printf "\e[01;31mERROR\033[0m: Mutagen 0.10.3 or greater is required (version ${MUTAGEN_VERSION} is installed)\n"
  INIT_ERROR=1
fi

## check for presence of local configuration files to ensure they exist
for REQUIRED_FILE in ${REQUIRED_FILES[@]}; do
  if [[ ! -f "${REQUIRED_FILE}" ]]; then
    >&2 printf "\e[01;31mERROR\033[0m: Missing local file: ${REQUIRED_FILE} \n"
    INIT_ERROR=1
  fi
done

## exit script if there are any missing dependencies or configuration files
[[ ${INIT_ERROR} ]] && exit 1

:: Starting Warden
warden up
if [[ ! -f ~/.warden/ssl/certs/${TRAEFIK_DOMAIN}.crt.pem ]]; then
    warden sign-certificate ${TRAEFIK_DOMAIN}
fi

:: Initializing environment
warden env pull --ignore-pull-failures    # With an overriden image on php-fpm container, there will be pull failures
warden env build --pull
warden env up -d

## wait for mariadb to start listening for connections
warden shell -c "while ! nc -z db 3306 </dev/null; do sleep 2; done"

## start sync session only on macOS systems
if [[ $OSTYPE =~ ^darwin ]]; then
  warden sync start
fi

:: Installing dependencies
warden env exec -T php-fpm composer global require hirak/prestissimo
warden env exec -T php-fpm composer install

## import database only if --skip-db-import is not specified
if [[ ${DB_IMPORT} ]]; then
  :: Importing database
  warden db connect -e 'drop database magento; create database magento;'
  pv "${DB_DUMP}" | gunzip -c | warden db import
elif [[ ${CLEAN_INSTALL} ]]; then
  :: Installing application
  warden env exec -- -T php-fpm rm -vf app/etc/config.php app/etc/env.php
  warden env exec -- -T php-fpm bin/magento setup:install \
      --cleanup-database \
      --backend-frontname=backend \
      --amqp-host=rabbitmq \
      --amqp-port=5672 \
      --amqp-user=guest \
      --amqp-password=guest \
      --consumers-wait-for-messages=0 \
      --db-host=db \
      --db-name=magento \
      --db-user=magento \
      --db-password=magento \
      --http-cache-hosts=varnish:80 \
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

  :: Configuring application
  warden env exec -T php-fpm php -r '
    $env = "<?php\nreturn " . var_export(array_merge_recursive(
      include("app/etc/env.php"),
      include("app/etc/env.php.init.php")
    ), true) . ";\n";
    file_put_contents("app/etc/env.php", $env);
  '
  warden env exec -T php-fpm cp -n app/etc/env.php app/etc/env.php.warden.php
  warden env exec -T php-fpm ln -fsn env.php.warden.php app/etc/env.php
  warden env exec -T php-fpm bin/magento app:config:import

  warden env exec -T php-fpm bin/magento config:set -q --lock-env web/unsecure/base_url ${URL_FRONT}
  warden env exec -T php-fpm bin/magento config:set -q --lock-env web/secure/base_url ${URL_FRONT}

  warden env exec -T php-fpm bin/magento deploy:mode:set -s developer
  warden env exec -T php-fpm bin/magento cache:disable block_html full_page
  warden env exec -T php-fpm bin/magento app:config:dump themes scopes i18n

  :: Rebuilding indexes
  warden env exec -T php-fpm bin/magento indexer:reindex
fi

if [[ ! ${CLEAN_INSTALL} ]]; then
  :: Configuring application
  warden env exec -T php-fpm ln -fsn env.php.warden.php app/etc/env.php

  :: Updating application
  warden env exec -T php-fpm bin/magento cache:flush
  warden env exec -T php-fpm bin/magento app:config:import
  warden env exec -T php-fpm bin/magento setup:db-schema:upgrade
  warden env exec -T php-fpm bin/magento setup:db-data:upgrade
fi

:: Flushing cache
warden env exec -T php-fpm bin/magento cache:flush

:: Creating admin user
ADMIN_PASS=$(warden env exec -T php-fpm pwgen -n1 16)
ADMIN_USER=localadmin

warden env exec -T php-fpm bin/magento admin:user:create \
    --admin-password="${ADMIN_PASS}" \
    --admin-user="${ADMIN_USER}" \
    --admin-firstname="Local" \
    --admin-lastname="Admin" \
    --admin-email="${ADMIN_USER}@example.com"

:: Initialization complete
function print_install_info {
    FILL=$(printf "%0.s-" {1..128})
    C1_LEN=8
    let "C2_LEN=${#URL_ADMIN}>${#ADMIN_PASS}?${#URL_ADMIN}:${#ADMIN_PASS}"

    # note: in CentOS bash .* isn't supported (is on Darwin), but *.* is more cross-platform
    printf "+ %*.*s + %*.*s + \n" 0 $C1_LEN $FILL 0 $C2_LEN $FILL
    printf "+ %-*s + %-*s + \n" $C1_LEN FrontURL $C2_LEN "$URL_FRONT"
    printf "+ %*.*s + %*.*s + \n" 0 $C1_LEN $FILL 0 $C2_LEN $FILL
    printf "+ %-*s + %-*s + \n" $C1_LEN AdminURL $C2_LEN "$URL_ADMIN"
    printf "+ %*.*s + %*.*s + \n" 0 $C1_LEN $FILL 0 $C2_LEN $FILL
    printf "+ %-*s + %-*s + \n" $C1_LEN Username $C2_LEN "$ADMIN_USER"
    printf "+ %*.*s + %*.*s + \n" 0 $C1_LEN $FILL 0 $C2_LEN $FILL
    printf "+ %-*s + %-*s + \n" $C1_LEN Password $C2_LEN "$ADMIN_PASS"
    printf "+ %*.*s + %*.*s + \n" 0 $C1_LEN $FILL 0 $C2_LEN $FILL
}
print_install_info
