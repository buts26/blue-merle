#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BLUE_MERLE_BUILD_DIR:-${ROOT_DIR}/.autobuild}"
PID_DIR="${BUILD_DIR}/pids"

stop_pid_file() {
  local name="$1"
  local pid_file="$2"

  if [[ ! -f "${pid_file}" ]]; then
    echo "${name}: not running"
    return 0
  fi

  local pid
  pid="$(cat "${pid_file}")"
  if kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}"
    echo "${name}: stopped PID ${pid}"
  else
    echo "${name}: stale PID ${pid}"
  fi

  rm -f "${pid_file}"
}

stop_pid_file "artifact-server" "${PID_DIR}/artifact-server.pid"
stop_pid_file "autobuild" "${PID_DIR}/autobuild.pid"
