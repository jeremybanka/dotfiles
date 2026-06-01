#!/bin/sh
set -eu

real_gh="/run/current-system/sw/bin/gh"
lib_path="${HOME}/.local/libexec/scrubs/clean-auth-lib.sh"

if [ ! -x "${real_gh}" ]; then
  echo "scrubs gh wrapper: missing real gh binary at ${real_gh}" >&2
  exit 1
fi

if [ -n "${GH_TOKEN:-}" ]; then
  exec "${real_gh}" "$@"
fi

case "${1-}:${2-}" in
  auth:login | auth:logout)
    exec "${real_gh}" "$@"
    ;;
esac

. "${lib_path}"

ciphertext_path="$(scrubs_clean_secret_path gh-token.enc)"
if ! scrubs_has_clean_secret "${ciphertext_path}"; then
  exec "${real_gh}" "$@"
fi

gh_token="$(scrubs_decrypt_clean_secret "${ciphertext_path}" | tr -d '\r\n')"
if [ -z "${gh_token}" ]; then
  echo "scrubs gh wrapper: decrypted an empty GitHub token" >&2
  exit 1
fi

GH_TOKEN="${gh_token}" exec "${real_gh}" "$@"
