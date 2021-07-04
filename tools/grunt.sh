#!/usr/bin/env bash
set -eu
trap 'error "$(printf "Command \`%s\` on line $LINENO failed with exit code $?" "$BASH_COMMAND")"' ERR

function error {
  >&2 printf "\033[31mERROR\033[0m: $@\n"
}

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
source .env
WARDEN_WEB_ROOT="$(echo "${WARDEN_WEB_ROOT:-/}" | sed 's#^/#./#')"
REQUIRED_FILES=("${WARDEN_WEB_ROOT}/package.json" "${WARDEN_WEB_ROOT}/Gruntfile.js")
GRUNT_ERROR=
WATCH=
THEME=

while (( "$#" )); do
    case "$1" in
        -w|--watch)
            WATCH=1
            shift
            THEME="$1"
            shift
            ;;
        -h|--help)
            echo "Usage: $(basename $0) [-w|--watch] <theme>"
            echo ""
            echo "       -w|--watch                Watch for file changes"
            echo ""
            exit -1
            ;;
        *)
            THEME="$1"
            shift
            ;;
    esac
done

## check for presence of local configuration files to ensure they exist
for REQUIRED_FILE in ${REQUIRED_FILES[@]}; do
  if [[ ! -f "${REQUIRED_FILE}" ]]; then
    error "Missing local file: ${REQUIRED_FILE}"
    GRUNT_ERROR=1
  fi
done

## exit script if there are any missing dependencies or configuration files
[[ ${GRUNT_ERROR} ]] && exit 1

:: Installing node dependencies
warden env exec -T php-fpm npm install

:: Compiling static assets
if [[ ${THEME} ]];
then
    warden env exec -T php-fpm grunt exec:${THEME}
    warden env exec -T php-fpm grunt less:${THEME}
else
    warden env exec -T php-fpm grunt exec
    warden env exec -T php-fpm grunt less
fi

if [[ ${WATCH} ]]; then
    warden env exec -T php-fpm grunt watch
fi
