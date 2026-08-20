#!/bin/sh
set -eu

CONFIG_FILE="${OPENVIKING_CONFIG_FILE:-/app/.openviking/ov.conf}"

# Proxies are a common bypass around destination checks. The UOS baseline only
# permits direct connections to audited intranet destinations.
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY FTP_PROXY http_proxy https_proxy all_proxy ftp_proxy
export NO_PROXY="*"

case "${OPENVIKING_NETWORK_MODE:-intranet}" in
    offline|intranet|online) ;;
    *)
        echo "[uos-policy] invalid OPENVIKING_NETWORK_MODE" >&2
        exit 2
        ;;
esac

if [ "$#" -eq 1 ] && [ "$1" = "--policy-check" ]; then
    exec python /opt/openviking-uos/validate_config.py "${CONFIG_FILE}"
fi

if [ "$#" -eq 1 ] && [ "$1" = "--policy-info" ]; then
    exec python -c 'from network_policy import describe_policy; print(describe_policy())'
fi

if [ "$#" -eq 0 ] || [ "${1:-}" = "--with-bot" ] || [ "${1:-}" = "--without-bot" ]; then
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "[uos-policy] configuration file not found: ${CONFIG_FILE}" >&2
        exit 2
    fi
    python /opt/openviking-uos/validate_config.py "${CONFIG_FILE}"
fi

exec /usr/local/bin/openviking-entrypoint "$@"
