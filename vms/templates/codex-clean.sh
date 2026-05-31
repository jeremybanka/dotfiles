#!/bin/sh
set -eu

real_codex="/run/current-system/sw/bin/codex"
lib_path="${HOME}/.local/libexec/scrubs/clean-auth-lib.sh"

if [ ! -x "${real_codex}" ]; then
  echo "scrubs codex wrapper: missing real codex binary at ${real_codex}" >&2
  exit 1
fi

if [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${CODEX_ACCESS_TOKEN:-}" ]; then
  exec "${real_codex}" "$@"
fi

if [ "${1-}" = "logout" ]; then
  exec "${real_codex}" "$@"
fi

if [ "${1-}" = "login" ] && [ "${2-}" != "status" ]; then
  exec "${real_codex}" "$@"
fi

. "${lib_path}"

ciphertext_path="$(scrubs_clean_secret_path codex-api-key.enc)"
if ! scrubs_has_clean_secret "${ciphertext_path}"; then
  exec "${real_codex}" "$@"
fi

codex_api_key="$(scrubs_decrypt_clean_secret "${ciphertext_path}" | tr -d '\r\n')"
if [ -z "${codex_api_key}" ]; then
  echo "scrubs codex wrapper: decrypted an empty API key" >&2
  exit 1
fi

OPENAI_API_KEY="${codex_api_key}" exec "${real_codex}" "$@"
