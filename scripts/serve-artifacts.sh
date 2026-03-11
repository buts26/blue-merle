#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BLUE_MERLE_BUILD_DIR:-${ROOT_DIR}/.autobuild}"
PUBLIC_DIR="${BLUE_MERLE_PUBLIC_DIR:-${BUILD_DIR}/public}"
PORT="${BLUE_MERLE_ARTIFACT_PORT:-8080}"

mkdir -p "${PUBLIC_DIR}"

printf '[artifact-server] Serving %s on 0.0.0.0:%s\n' "${PUBLIC_DIR}" "${PORT}"
exec python3 -m http.server "${PORT}" --bind 0.0.0.0 --directory "${PUBLIC_DIR}"
