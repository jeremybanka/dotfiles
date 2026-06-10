#!/bin/sh
set -eu

scrubs_dir="${HOME}/.local/libexec/scrubs"
nu_bin="/run/current-system/sw/bin/nu"
mode_file="${scrubs_dir}/sandbox-policy-mode"
policy_file="${scrubs_dir}/sandbox-policy.nuon"
nu_script="${scrubs_dir}/install-dirty-tools.nu"
legacy_script="${scrubs_dir}/install-dirty-tools-legacy.sh"
mode=""

if [ -f "${mode_file}" ]; then
  mode="$(cat "${mode_file}")"
fi

if [ "${mode}" != "legacy-shell" ] \
  && [ -x "${nu_bin}" ] \
  && [ -f "${policy_file}" ] \
  && [ -f "${nu_script}" ]; then
  exec "${nu_bin}" "${nu_script}"
fi

exec "${legacy_script}" "$@"
