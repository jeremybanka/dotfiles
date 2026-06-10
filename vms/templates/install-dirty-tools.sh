#!/bin/sh
set -eu

scrubs_dir="${HOME}/.local/libexec/scrubs"
nu_bin="/run/current-system/sw/bin/nu"
policy_file="${scrubs_dir}/sandbox-policy.nuon"
nu_script="${scrubs_dir}/install-dirty-tools.nu"
shared_lib="${scrubs_dir}/sandbox-policy-lib.nu"
legacy_script="${scrubs_dir}/install-dirty-tools-legacy.sh"

if [ -x "${nu_bin}" ] \
  && [ -f "${policy_file}" ] \
  && [ -f "${nu_script}" ] \
  && [ -f "${shared_lib}" ]; then
  exec "${nu_bin}" "${nu_script}"
fi

exec "${legacy_script}" "$@"
