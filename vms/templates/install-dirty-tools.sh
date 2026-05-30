#!/bin/sh
set -eu

scrubs_dir="${HOME}/.local/libexec/scrubs"
proxy_dir="${HOME}/.local/bin"
helper_root="${HOME}/.local/share/scrubs/helper-root"
dirty_exec="${scrubs_dir}/dirty-exec.sh"
mise_wrapper="${scrubs_dir}/mise-wrapper.sh"
mise_shims_dir="${HOME}/.local/share/mise/shims"

mkdir -p "${proxy_dir}" "${helper_root}/bin" "${helper_root}/usr/bin" "${helper_root}/etc/ssl/certs"

copy_text_file() {
  src="$1"
  dst="$2"

  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    rm -f "$dst"
    cp "$src" "$dst"
    chmod u+w "$dst"
  fi
}

link_helper() {
  resolved="$(readlink -f "$1")"
  dst="$2"

  mkdir -p "$(dirname "$dst")"
  ln -snf "$resolved" "$dst"
}

resolve_command_path() {
  command_name="$1"
  if [ -x "/run/current-system/sw/bin/${command_name}" ]; then
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

copy_text_file /etc/passwd "${helper_root}/etc/passwd"
copy_text_file /etc/group "${helper_root}/etc/group"
copy_text_file /etc/nsswitch.conf "${helper_root}/etc/nsswitch.conf"

if [ -f /etc/ssl/certs/ca-bundle.crt ]; then
  link_helper /etc/ssl/certs/ca-bundle.crt "${helper_root}/etc/ssl/certs/ca-bundle.crt"
fi

link_helper "$(command -v bash)" "${helper_root}/bin/bash"
ln -snf bash "${helper_root}/bin/sh"

for command_name in \
  awk basename cat chmod cp cut dirname env find git grep head id ln ls mkdir mktemp pwd \
  readlink rm sed sh sort tail tar tee touch tr uname uniq which xargs xz gzip unzip mise
do
  resolved="$(resolve_command_path "$command_name")"
  if [ -n "${resolved}" ]; then
    link_helper "${resolved}" "${helper_root}/usr/bin/${command_name}"
  fi
done

for proxy_path in "${proxy_dir}"/*; do
  [ -e "${proxy_path}" ] || continue
  if [ "$(readlink "${proxy_path}" 2>/dev/null || true)" = "${dirty_exec}" ]; then
    rm -f "${proxy_path}"
  fi
done

ln -snf "${dirty_exec}" "${proxy_dir}/scrubs-dirty-exec"
cp "${mise_wrapper}" "${proxy_dir}/mise"
chmod 755 "${proxy_dir}/mise"

if [ -d "${mise_shims_dir}" ]; then
  for shim_path in "${mise_shims_dir}"/*; do
    [ -f "${shim_path}" ] || continue
    command_name="$(basename "${shim_path}")"
    case "${command_name}" in
      mise)
        continue
        ;;
    esac
    ln -snf "${dirty_exec}" "${proxy_dir}/${command_name}"
  done
fi
