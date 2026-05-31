#!/bin/bash
set -euo pipefail

scrubs_dir="${HOME}/.local/libexec/scrubs"
proxy_dir="${HOME}/.local/bin"
helper_root="${HOME}/.local/share/scrubs/helper-root"
dirty_exec="${scrubs_dir}/dirty-exec.sh"
mise_wrapper="${scrubs_dir}/mise-wrapper.sh"
sandbox_definition="${scrubs_dir}/sandbox-definition.sh"
mise_shims_dir="${HOME}/.local/share/mise/shims"

mkdir -p "${proxy_dir}" "${helper_root}/bin" "${helper_root}/usr/bin" "${helper_root}/etc/ssl/certs"

if [[ ! -f "${sandbox_definition}" ]]; then
  echo "scrubs dirty tools: missing sandbox definition at ${sandbox_definition}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${sandbox_definition}"

copy_text_file() {
  local src="$1"
  local dst="$2"

  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    rm -f "$dst"
    cp "$src" "$dst"
    chmod u+w "$dst"
  fi
}

link_helper() {
  local resolved
  local dst="$2"

  resolved="$(readlink -f "$1")"

  mkdir -p "$(dirname "$dst")"
  ln -snf "$resolved" "$dst"
}

resolve_command_path() {
  local command_name="$1"
  local resolved

  if [[ -x "/run/current-system/sw/bin/${command_name}" ]]; then
    printf '%s\n' "/run/current-system/sw/bin/${command_name}"
    return 0
  fi

  resolved="$(command -v "$command_name" 2>/dev/null || true)"
  case "$resolved" in
    /*)
      printf '%s\n' "$resolved"
      ;;
  esac
}

for helper_file in "${SCRUBS_HELPER_COPY_FILES[@]}"; do
  copy_text_file "${helper_file}" "${helper_root}${helper_file}"
done

for helper_file in "${SCRUBS_HELPER_LINK_FILES[@]}"; do
  if [[ -e "${helper_file}" ]]; then
    link_helper "${helper_file}" "${helper_root}${helper_file}"
  fi
done

link_helper "$(resolve_command_path "${SCRUBS_PRIMARY_SHELL}")" "${helper_root}/bin/${SCRUBS_PRIMARY_SHELL}"
ln -snf "${SCRUBS_PRIMARY_SHELL}" "${helper_root}/bin/sh"

for command_name in "${SCRUBS_HELPER_COMMANDS[@]}"; do
  resolved="$(resolve_command_path "$command_name")"
  if [[ -n "${resolved}" ]]; then
    link_helper "${resolved}" "${helper_root}/usr/bin/${command_name}"
  fi
done

for proxy_path in "${proxy_dir}"/*; do
  [[ -e "${proxy_path}" ]] || continue
  if [[ "$(readlink "${proxy_path}" 2>/dev/null || true)" == "${dirty_exec}" ]]; then
    rm -f "${proxy_path}"
  fi
done

ln -snf "${dirty_exec}" "${proxy_dir}/scrubs-dirty-exec"
cp "${mise_wrapper}" "${proxy_dir}/mise"
chmod 755 "${proxy_dir}/mise"

if [[ -d "${mise_shims_dir}" ]]; then
  for shim_path in "${mise_shims_dir}"/*; do
    [[ -f "${shim_path}" ]] || continue
    command_name="$(basename "${shim_path}")"
    case "${command_name}" in
      mise)
        continue
        ;;
    esac
    ln -snf "${dirty_exec}" "${proxy_dir}/${command_name}"
  done
fi
