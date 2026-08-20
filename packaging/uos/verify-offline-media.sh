#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_SMOKE=0
[[ "${1:-}" == "--docker-smoke" ]] && DOCKER_SMOKE=1

(cd "${ROOT_DIR}" && sha256sum -c --strict SHA256SUMS)
python3 - "${ROOT_DIR}/manifest.json" <<'PY'
import json, platform, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
assert manifest["schema_version"] == 1
assert manifest["target"]["os"] == "linux"
assert manifest["target"]["architecture"] == "amd64"
assert manifest["install"]["network_required"] is False
print("manifest accepted:", manifest["release"])
PY

IMAGE_ARCHIVE="$(find "${ROOT_DIR}/images" -maxdepth 1 -type f -name '*linux-amd64*.tar.gz' -print -quit)"
[[ -n "${IMAGE_ARCHIVE}" ]] || { echo "Image archive missing" >&2; exit 2; }
gzip -t "${IMAGE_ARCHIVE}"

if [[ "${DOCKER_SMOKE}" -eq 0 ]]; then
  echo "Offline media integrity passed (Docker smoke skipped)"
  exit 0
fi

command -v docker >/dev/null || { echo "Docker is required for --docker-smoke" >&2; exit 2; }
docker info >/dev/null
LOAD_OUTPUT="$(docker load -i "${IMAGE_ARCHIVE}")"
printf '%s\n' "${LOAD_OUTPUT}"
IMAGE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["name"])' "${ROOT_DIR}/manifest.json")"
CONTAINER="openviking-uos-offline-smoke-$$"
TMP_DIR="$(mktemp -d)"
cleanup() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
  rm -rf -- "${TMP_DIR}"
}
trap cleanup EXIT

cp "${ROOT_DIR}/config/ov.conf.example" "${TMP_DIR}/ov.conf"
cp "${ROOT_DIR}/config/ovcli.conf.example" "${TMP_DIR}/ovcli.conf"
chmod 600 "${TMP_DIR}"/*.conf

COMMON_ENV=(
  -e OPENVIKING_NETWORK_MODE=offline
  -e OPENVIKING_ROOT_API_KEY=offline-smoke-root-api-key-00000001
  -e OPENVIKING_EMBEDDING_API_BASE=http://127.0.0.1:19998/v1
  -e OPENVIKING_EMBEDDING_API_KEY=offline-smoke-embedding-key
  -e OPENVIKING_EMBEDDING_MODEL=offline-smoke-embedding
  -e OPENVIKING_VLM_API_BASE=http://127.0.0.1:19999/v1
  -e OPENVIKING_VLM_API_KEY=offline-smoke-vlm-key
  -e OPENVIKING_VLM_MODEL=offline-smoke-vlm
)

docker run --rm --network none "${COMMON_ENV[@]}" -v "${TMP_DIR}:/app/.openviking" "${IMAGE}" --policy-check
docker run --rm --network none -e OPENVIKING_NETWORK_MODE=offline "${IMAGE}" \
  python -c 'import socket; socket.getaddrinfo("example.com", 443)' >/dev/null 2>"${TMP_DIR}/blocked.log" && {
    echo "Public DNS policy unexpectedly allowed example.com" >&2
    exit 1
  }
grep -q "network policy blocked" "${TMP_DIR}/blocked.log"

docker run -d --name "${CONTAINER}" --network none "${COMMON_ENV[@]}" \
  -v "${TMP_DIR}:/app/.openviking" "${IMAGE}" --without-bot >/dev/null

for _ in $(seq 1 90); do
  if docker exec "${CONTAINER}" curl -fsS http://127.0.0.1:1933/health >/dev/null 2>&1; then
    echo "No-network server health smoke passed"
    exit 0
  fi
  if [[ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}")" != "true" ]]; then
    docker logs "${CONTAINER}" >&2
    exit 1
  fi
  sleep 1
done
docker logs "${CONTAINER}" >&2
echo "Timed out waiting for no-network health" >&2
exit 1
