#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BLUE_MERLE_BUILD_DIR:-${ROOT_DIR}/.autobuild}"
LOG_DIR="${BUILD_DIR}/logs"
PID_DIR="${BUILD_DIR}/pids"
PUBLIC_IP="${BLUE_MERLE_PUBLIC_IP:-57.128.248.236}"
PORT="${BLUE_MERLE_ARTIFACT_PORT:-8080}"

mkdir -p "${LOG_DIR}" "${PID_DIR}"

if [[ -f "${PID_DIR}/autobuild.pid" ]] && kill -0 "$(cat "${PID_DIR}/autobuild.pid")" 2>/dev/null; then
  echo "Autobuild already running with PID $(cat "${PID_DIR}/autobuild.pid")"
else
  nohup "${ROOT_DIR}/scripts/autobuild-openwrt.sh" > "${LOG_DIR}/autobuild.log" 2>&1 &
  echo "$!" > "${PID_DIR}/autobuild.pid"
  echo "Started autobuild (PID $!)"
fi

if [[ -f "${PID_DIR}/artifact-server.pid" ]] && kill -0 "$(cat "${PID_DIR}/artifact-server.pid")" 2>/dev/null; then
  echo "Artifact server already running with PID $(cat "${PID_DIR}/artifact-server.pid")"
else
  nohup "${ROOT_DIR}/scripts/serve-artifacts.sh" > "${LOG_DIR}/artifact-server.log" 2>&1 &
  echo "$!" > "${PID_DIR}/artifact-server.pid"
  echo "Started artifact server (PID $!)"
fi

echo
echo "Public artifacts URL: http://${PUBLIC_IP}:${PORT}/latest/"
echo "Build history URL:    http://${PUBLIC_IP}:${PORT}/builds/"
