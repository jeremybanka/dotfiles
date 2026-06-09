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

copy_legacy_runtime_codex_home() {
  legacy_codex_home="$1"
  durable_codex_home="$2"

  if [ ! -d "${legacy_codex_home}" ] || [ "${legacy_codex_home}" = "${durable_codex_home}" ]; then
    return 0
  fi

  # Migrate prior tmpfs-backed chat/session state forward, but keep auth ephemeral.
  if ! (cd "${legacy_codex_home}" && tar -cf - --exclude=./auth.json .) \
    | (cd "${durable_codex_home}" && tar -xf -); then
    echo "scrubs codex wrapper: failed to migrate legacy runtime Codex state" >&2
    return 1
  fi
}

ciphertext_path="$(scrubs_clean_secret_path codex-auth.json.enc)"
if ! scrubs_has_clean_secret "${ciphertext_path}"; then
  exec "${real_codex}" "$@"
fi

runtime_auth_dir="$(scrubs_runtime_auth_dir)"
runtime_auth_json="${runtime_auth_dir}/codex-auth.json"
legacy_runtime_codex_home="${runtime_auth_dir}/codex-home"
guest_codex_home="${HOME}/.codex"
guest_auth_json="${guest_codex_home}/auth.json"

umask 077
mkdir -p "${guest_codex_home}"
chmod 700 "${guest_codex_home}"

copy_legacy_runtime_codex_home "${legacy_runtime_codex_home}" "${guest_codex_home}"

if ! scrubs_materialize_runtime_secret "${ciphertext_path}" "${runtime_auth_json}"; then
  echo "scrubs codex wrapper: failed to materialize the sealed auth bundle" >&2
  exit 1
fi

if ! grep -Eq '"auth_mode"[[:space:]]*:[[:space:]]*"chatgpt"' "${runtime_auth_json}"; then
  echo "scrubs codex wrapper: runtime auth bundle is not using ChatGPT auth mode" >&2
  exit 1
fi

ln -snf "${runtime_auth_json}" "${guest_auth_json}"

exec "${real_codex}" "$@"
