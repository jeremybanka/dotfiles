#!/bin/sh
set -eu

real_codex="/run/current-system/sw/bin/codex"
lib_path="${HOME}/.local/libexec/scrubs/clean-auth-lib.sh"

if [ ! -x "${real_codex}" ]; then
  echo "scrubs codex wrapper: missing real codex binary at ${real_codex}" >&2
  exit 1
fi

if [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${CODEX_ACCESS_TOKEN:-}" ] || [ -n "${CODEX_HOME:-}" ]; then
  exec "${real_codex}" "$@"
fi

. "${lib_path}"

ciphertext_path="$(scrubs_clean_secret_path codex-auth.json.enc)"
if ! scrubs_has_clean_secret "${ciphertext_path}"; then
  exec "${real_codex}" "$@"
fi

runtime_auth_dir="$(scrubs_runtime_auth_dir)"
runtime_codex_home="${runtime_auth_dir}/codex-home"
runtime_auth_json="${runtime_codex_home}/auth.json"
guest_codex_config_dir="${HOME}/.codex"
guest_codex_config="${guest_codex_config_dir}/config.toml"

umask 077
mkdir -p "${runtime_codex_home}"
chmod 700 "${runtime_codex_home}"

if [ -f "${guest_codex_config}" ]; then
  ln -snf "${guest_codex_config}" "${runtime_codex_home}/config.toml"
fi

if ! scrubs_materialize_runtime_secret "${ciphertext_path}" "${runtime_auth_json}"; then
  echo "scrubs codex wrapper: failed to materialize the sealed auth bundle" >&2
  exit 1
fi

if ! grep -Eq '"auth_mode"[[:space:]]*:[[:space:]]*"chatgpt"' "${runtime_auth_json}"; then
  echo "scrubs codex wrapper: runtime auth bundle is not using ChatGPT auth mode" >&2
  exit 1
fi

CODEX_HOME="${runtime_codex_home}" exec "${real_codex}" "$@"
