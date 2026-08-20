#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${INSTALL_DIR}"

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "Docker Compose is required" >&2
    exit 2
  fi
}

require_ready_config() {
  [[ -f .env ]] || { echo "Missing ${INSTALL_DIR}/.env" >&2; exit 2; }
  if grep -Eq 'change-me|replace-with|intra\.example' .env; then
    echo "Replace all placeholders in ${INSTALL_DIR}/.env before starting" >&2
    exit 2
  fi
  compose config --quiet
  compose run --rm --no-deps openviking --policy-check
}

case "${1:-}" in
  up)
    require_ready_config
    compose up -d
    compose ps
    ;;
  down)
    compose down
    ;;
  stop)
    compose stop
    ;;
  restart)
    require_ready_config
    compose up -d --force-recreate
    ;;
  status)
    compose ps
    ;;
  logs)
    compose logs --tail="${2:-200}" openviking
    ;;
  policy-check)
    require_ready_config
    ;;
  doctor)
    compose exec openviking openviking-server doctor
    ;;
  smoke)
    compose exec openviking curl -fsS http://127.0.0.1:1933/health
    ;;
  *)
    echo "Usage: $0 {up|down|stop|restart|status|logs [LINES]|policy-check|doctor|smoke}" >&2
    exit 2
    ;;
esac
