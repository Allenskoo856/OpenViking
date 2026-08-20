#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/packaging/uos/release.env"
OUTPUT_DIR="${1:-${ROOT_DIR}/dist}"
SOURCE_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
MEDIA_NAME="openviking-uos-offline-${UOS_RELEASE}-linux-amd64"
STAGE_ROOT="$(mktemp -d)"
STAGE_DIR="${STAGE_ROOT}/${MEDIA_NAME}"

cleanup() { rm -rf -- "${STAGE_ROOT}"; }
trap cleanup EXIT

command -v docker >/dev/null || { echo "docker is required in the connected build zone" >&2; exit 2; }
mkdir -p "${OUTPUT_DIR}" "${STAGE_DIR}/images" "${STAGE_DIR}/config" "${STAGE_DIR}/docs"

docker build --platform "${TARGET_PLATFORM}" \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  --label "org.opencontainers.image.version=${UOS_RELEASE}" \
  --label "org.opencontainers.image.revision=${SOURCE_COMMIT}" \
  --label "org.opencontainers.image.source=https://github.com/Allenskoo856/OpenViking" \
  -f "${ROOT_DIR}/packaging/uos/Dockerfile" \
  -t "${OUTPUT_IMAGE}" "${ROOT_DIR}"

IMAGE_ARCHIVE="${STAGE_DIR}/images/openviking-${UOS_RELEASE}-linux-amd64.tar.gz"
docker save "${OUTPUT_IMAGE}" | gzip -9 > "${IMAGE_ARCHIVE}"
IMAGE_ID="$(docker image inspect "${OUTPUT_IMAGE}" --format '{{.Id}}')"

cp "${ROOT_DIR}/packaging/uos/docker-compose.yml" "${STAGE_DIR}/docker-compose.yml"
cp "${ROOT_DIR}/packaging/uos/install-offline.sh" "${STAGE_DIR}/install-offline.sh"
cp "${ROOT_DIR}/packaging/uos/manage.sh" "${STAGE_DIR}/manage.sh"
cp "${ROOT_DIR}/packaging/uos/uninstall-offline.sh" "${STAGE_DIR}/uninstall-offline.sh"
cp "${ROOT_DIR}/packaging/uos/verify-offline-media.sh" "${STAGE_DIR}/verify-offline-media.sh"
cp "${ROOT_DIR}/packaging/uos/config/ov.conf.example" "${STAGE_DIR}/config/ov.conf.example"
cp "${ROOT_DIR}/packaging/uos/config/ovcli.conf.example" "${STAGE_DIR}/config/ovcli.conf.example"
cp "${ROOT_DIR}/packaging/uos/config/.env.example" "${STAGE_DIR}/config/.env.example"
cp "${ROOT_DIR}/docs/intranet/offline-deployment-zh-CN.md" "${STAGE_DIR}/docs/"
cp "${ROOT_DIR}/docs/intranet/configuration-zh-CN.md" "${STAGE_DIR}/docs/"
cp "${ROOT_DIR}/LICENSE" "${STAGE_DIR}/LICENSE"
chmod 0755 "${STAGE_DIR}"/*.sh

python3 - "${STAGE_DIR}/manifest.json" <<PY
import json, sys
manifest = {
  "schema_version": 1,
  "release": "${UOS_RELEASE}",
  "upstream_version": "${UPSTREAM_VERSION}",
  "source": {
    "repository": "https://github.com/Allenskoo856/OpenViking",
    "commit": "${SOURCE_COMMIT}",
    "upstream_repository": "https://github.com/volcengine/OpenViking"
  },
  "target": {"os": "linux", "architecture": "amd64", "tested_baseline": "Debian 10 compatible container host"},
  "image": {"name": "${OUTPUT_IMAGE}", "id": "${IMAGE_ID}", "base": "${BASE_IMAGE}"},
  "install": {"network_required": False, "container_runtime_required": True},
  "runtime": {
    "public_internet_required": False,
    "semantic_features_require_intranet_model_endpoints": True,
    "default_network_mode": "intranet",
    "telemetry_enabled": False,
    "vikingbot_enabled": False
  }
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

(cd "${STAGE_DIR}" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
ARCHIVE="${OUTPUT_DIR}/${MEDIA_NAME}.tar.gz"
tar -C "${STAGE_ROOT}" -czf "${ARCHIVE}" "${MEDIA_NAME}"
cp "${STAGE_DIR}/manifest.json" "${OUTPUT_DIR}/${MEDIA_NAME}.manifest.json"
(
  cd "${OUTPUT_DIR}"
  sha256sum "$(basename "${ARCHIVE}")" "${MEDIA_NAME}.manifest.json" > SHA256SUMS
)
echo "Built ${ARCHIVE}"
