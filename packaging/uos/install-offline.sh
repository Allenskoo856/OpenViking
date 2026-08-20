#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/openviking-uos"
DATA_DIR="/var/lib/openviking"
START_AFTER_INSTALL=0

usage() {
  echo "Usage: $0 [--install-dir DIR] [--data-dir DIR] [--start]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    --start) START_AFTER_INSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || { echo "Only Linux is supported" >&2; exit 2; }
case "$(uname -m)" in x86_64|amd64) ;; *) echo "Only Linux x86_64 is supported" >&2; exit 2 ;; esac
command -v docker >/dev/null || { echo "docker is required and must be provisioned from the intranet" >&2; exit 2; }
docker info >/dev/null || { echo "Docker engine is unavailable" >&2; exit 2; }

IMAGE_ARCHIVE="$(find "${SCRIPT_DIR}/images" -maxdepth 1 -type f -name '*linux-amd64*.tar.gz' -print -quit)"
[[ -n "${IMAGE_ARCHIVE}" ]] || { echo "Offline image archive is missing" >&2; exit 2; }

mkdir -p "${INSTALL_DIR}" "${DATA_DIR}"
[[ -w "${INSTALL_DIR}" && -w "${DATA_DIR}" ]] || {
  echo "No write permission for ${INSTALL_DIR} or ${DATA_DIR}; run with sudo or choose writable directories" >&2
  exit 2
}

if [[ -f "${SCRIPT_DIR}/SHA256SUMS" ]]; then
  (cd "${SCRIPT_DIR}" && sha256sum -c --strict SHA256SUMS)
fi

echo "Loading offline image: ${IMAGE_ARCHIVE}"
docker load -i "${IMAGE_ARCHIVE}"

BACKUP_DIR=""
if [[ -f "${INSTALL_DIR}/manifest.json" ]]; then
  BACKUP_DIR="${INSTALL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
  mkdir -p "${BACKUP_DIR}"
  cp -a "${INSTALL_DIR}/manifest.json" "${INSTALL_DIR}/docker-compose.yml" "${INSTALL_DIR}/manage.sh" "${BACKUP_DIR}/" 2>/dev/null || true
  echo "Previous management files backed up to ${BACKUP_DIR}"
fi

install -m 0644 "${SCRIPT_DIR}/manifest.json" "${INSTALL_DIR}/manifest.json"
install -m 0644 "${SCRIPT_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
install -m 0755 "${SCRIPT_DIR}/manage.sh" "${INSTALL_DIR}/manage.sh"
install -m 0755 "${SCRIPT_DIR}/uninstall-offline.sh" "${INSTALL_DIR}/uninstall-offline.sh"
mkdir -p "${INSTALL_DIR}/docs"
cp -a "${SCRIPT_DIR}/docs/." "${INSTALL_DIR}/docs/"

if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
  install -m 0600 "${SCRIPT_DIR}/config/.env.example" "${INSTALL_DIR}/.env"
fi
if [[ ! -f "${DATA_DIR}/ov.conf" ]]; then
  install -m 0600 "${SCRIPT_DIR}/config/ov.conf.example" "${DATA_DIR}/ov.conf"
fi
if [[ ! -f "${DATA_DIR}/ovcli.conf" ]]; then
  install -m 0600 "${SCRIPT_DIR}/config/ovcli.conf.example" "${DATA_DIR}/ovcli.conf"
fi

sed -i "s|^OPENVIKING_DATA_DIR=.*|OPENVIKING_DATA_DIR=${DATA_DIR}|" "${INSTALL_DIR}/.env"

echo "Installed management files to ${INSTALL_DIR}; data/config preserved in ${DATA_DIR}"
echo "Next: edit ${INSTALL_DIR}/.env and ${DATA_DIR}/ov.conf, then run ${INSTALL_DIR}/manage.sh up"

if [[ "${START_AFTER_INSTALL}" -eq 1 ]]; then
  "${INSTALL_DIR}/manage.sh" up
fi
