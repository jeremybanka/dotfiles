#!/bin/sh
set -eu

real_mise="/run/current-system/sw/bin/mise"
refresh_script="${HOME}/.local/libexec/scrubs/install-dirty-tools.nu"
nu_bin="/run/current-system/sw/bin/nu"
rustup_home="${HOME}/.local/share/mise/rustup-home"
rust_bootstrap_cargo_home="${HOME}/.local/share/mise/rust-cargo-home"

# Keep rustup-managed toolchains in a scrubs-owned mise subtree rather than
# the clean home defaults so dirtyspace can consume only the intended surface.
: "${RUSTUP_HOME:=${rustup_home}}"
: "${CARGO_HOME:=${rust_bootstrap_cargo_home}}"
export RUSTUP_HOME CARGO_HOME

set +e
"${real_mise}" "$@"
status=$?
set -e

if [ "${status}" -eq 0 ] && [ -x "${nu_bin}" ] && [ -f "${refresh_script}" ]; then
  "${nu_bin}" "${refresh_script}" > /dev/null 2>&1 || true
fi

exit "${status}"
