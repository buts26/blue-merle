#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BLUE_MERLE_BUILD_DIR:-${ROOT_DIR}/.autobuild}"
PUBLIC_DIR="${BLUE_MERLE_PUBLIC_DIR:-${BUILD_DIR}/public}"
STATE_FILE="${BUILD_DIR}/last-built-commit"
LOG_DIR="${BUILD_DIR}/logs"
POLL_SECONDS="${BLUE_MERLE_POLL_SECONDS:-60}"

PACKAGE_NAME="${BLUE_MERLE_PACKAGE_NAME:-blue-merle}"
SDK_URL="${BLUE_MERLE_SDK_URL:-https://downloads.openwrt.org/releases/23.05.0/targets/ath79/nand/openwrt-sdk-23.05.0-ath79-nand_gcc-12.3.0_musl.Linux-x86_64.tar.xz}"
SDK_FILENAME="${BLUE_MERLE_SDK_FILENAME:-openwrt-sdk-23.05.0-ath79-nand_gcc-12.3.0_musl.Linux-x86_64.tar.xz}"
SDK_ROOT="${BUILD_DIR}/sdk/${SDK_FILENAME%.tar.xz}"

MODE="watch"
if [[ "${1:-}" == "--once" ]]; then
  MODE="once"
elif [[ "${1:-}" == "--force" ]]; then
  MODE="once"
  rm -f "${BUILD_DIR}/last-built-commit"
  log "Forced rebuild: state cleared."
fi

log() {
  printf '[autobuild] %s\n' "$*"
}

ensure_sdk() {
  mkdir -p "${BUILD_DIR}/sdk" "${PUBLIC_DIR}/builds" "${LOG_DIR}"

  if [[ ! -d "${SDK_ROOT}" ]]; then
    if [[ ! -f "${BUILD_DIR}/sdk/${SDK_FILENAME}" ]]; then
      log "Downloading OpenWrt SDK..."
      wget -q --show-progress -O "${BUILD_DIR}/sdk/${SDK_FILENAME}" "${SDK_URL}"
    fi

    log "Extracting OpenWrt SDK..."
    tar -xf "${BUILD_DIR}/sdk/${SDK_FILENAME}" -C "${BUILD_DIR}/sdk"
  fi
}

prepare_package_dir() {
  mkdir -p "${SDK_ROOT}/package/${PACKAGE_NAME}"
  rm -f "${SDK_ROOT}/package/${PACKAGE_NAME}/Makefile"
  rm -f "${SDK_ROOT}/package/${PACKAGE_NAME}/files"
  ln -s "${ROOT_DIR}/Makefile" "${SDK_ROOT}/package/${PACKAGE_NAME}/Makefile"
  ln -s "${ROOT_DIR}/files" "${SDK_ROOT}/package/${PACKAGE_NAME}/files"
}

prepare_config_and_feeds() {
  if [[ ! -f "${SDK_ROOT}/.blue-merle-sdk-prepared" ]]; then
    log "Updating OpenWrt package feeds..."
    (
      cd "${SDK_ROOT}"
      scripts/feeds update packages >/dev/null
      echo "CONFIG_SIGNED_PACKAGES=n" > .config
      make defconfig >/dev/null
      touch .blue-merle-sdk-prepared
    )
  fi
}

current_content_hash() {
  # Hash = git commit + hash of any uncommitted changes to tracked files.
  # Falls back to timestamp when not in a git repo.
  local commit
  commit="$(git -C "${ROOT_DIR}" rev-parse HEAD 2>/dev/null || echo 'no-git')"

  # Include staged + unstaged diff so even unsaved edits trigger a rebuild.
  local diff_hash
  diff_hash="$(git -C "${ROOT_DIR}" diff HEAD 2>/dev/null | sha256sum | cut -c1-16)"

  echo "${commit}-${diff_hash}"
}

should_build() {
  local hash
  hash="$(current_content_hash)"

  if [[ ! -f "${STATE_FILE}" ]]; then
    echo "${hash}"
    return 0
  fi

  if [[ "${hash}" != "$(cat "${STATE_FILE}")" ]]; then
    echo "${hash}"
    return 0
  fi

  return 1
}

collect_artifacts() {
  local commit="$1"
  local stamp
  local out_dir
  stamp="$(date +%Y%m%d-%H%M%S)"
  out_dir="${PUBLIC_DIR}/builds/${stamp}-${commit:0:8}"

  mkdir -p "${out_dir}"
  cp -f "${SDK_ROOT}/bin/packages/mips_24kc/base/${PACKAGE_NAME}"*.ipk "${out_dir}/"

  cat > "${out_dir}/build-info.txt" <<EOF
commit=${commit}
timestamp=${stamp}
package=${PACKAGE_NAME}
EOF

  ln -sfn "${out_dir}" "${PUBLIC_DIR}/latest"
}

build_once() {
  local hash
  hash="$(current_content_hash)"
  local short="${hash:0:16}"
  local logfile="${LOG_DIR}/build-${short}.log"

  log "Cleaning previous build artifacts..."
  (
    cd "${SDK_ROOT}"
    make -j"$(nproc)" V=s "package/${PACKAGE_NAME}/clean" >> "${logfile}" 2>&1 || true
  )

  log "Building package (hash ${short})..."
  (
    cd "${SDK_ROOT}"
    make -j"$(nproc)" V=s "package/${PACKAGE_NAME}/compile" \
      2>&1 | tee -a "${logfile}"
    make -j1 V=s package/index >> "${logfile}" 2>&1
  )

  collect_artifacts "${short}"
  printf '%s' "${hash}" > "${STATE_FILE}"
  log "Build finished. Artifacts are in ${PUBLIC_DIR}/latest"
}

run_watch() {
  while true; do
    if commit_to_build="$(should_build)"; then
      log "Change detected (${commit_to_build}), starting build..."
      build_once
    else
      log "No changes detected. Next check in ${POLL_SECONDS}s."
    fi
    sleep "${POLL_SECONDS}"
  done
}

ensure_sdk
prepare_package_dir
prepare_config_and_feeds

if [[ "${MODE}" == "once" ]]; then
  build_once
else
  run_watch
fi
