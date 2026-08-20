#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REMOVE_DATA=0
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove-data) REMOVE_DATA=1; shift ;;
    --confirm-remove-data) CONFIRM="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--remove-data --confirm-remove-data DELETE_OPENVIKING_DATA]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "${INSTALL_DIR}"
if docker compose version >/dev/null 2>&1; then
  docker compose down || true
elif command -v docker-compose >/dev/null 2>&1; then
  docker-compose down || true
fi

DATA_DIR="$(sed -n 's/^OPENVIKING_DATA_DIR=//p' .env 2>/dev/null | tail -n 1)"
echo "Containers removed. Management directory and data remain in place."

if [[ "${REMOVE_DATA}" -eq 1 ]]; then
  [[ "${CONFIRM}" == "DELETE_OPENVIKING_DATA" ]] || {
    echo "Data removal requires --confirm-remove-data DELETE_OPENVIKING_DATA" >&2
    exit 2
  }
  [[ -n "${DATA_DIR}" && "${DATA_DIR}" != "/" && "${DATA_DIR}" != "/var" ]] || {
    echo "Refusing unsafe data directory: ${DATA_DIR:-<empty>}" >&2
    exit 2
  }
  rm -rf -- "${DATA_DIR}"
  echo "Deleted ${DATA_DIR}; this cannot be recovered by this script."
fi
