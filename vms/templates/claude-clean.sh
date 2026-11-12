#!/bin/sh
set -eu

real_claude="/run/current-system/sw/bin/claude"
lib_path="${HOME}/.local/libexec/scrubs/clean-auth-lib.sh"

if [ ! -x "${real_claude}" ]; then
  echo "scrubs claude wrapper: missing real claude binary at ${real_claude}" >&2
  exit 1
fi

# Explicit credentials win, and an interactive `claude auth login` in the
# guest stays authoritative because sealed long-lived tokens are inference-only.
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] \
  || [ -n "${ANTHROPIC_API_KEY:-}" ] \
  || [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] \
  || [ -f "${HOME}/.claude/.credentials.json" ]; then
  exec "${real_claude}" "$@"
fi

case "${1-}:${2-}" in
  auth:login | auth:logout | setup-token:*)
    exec "${real_claude}" "$@"
    ;;
esac

. "${lib_path}"

ciphertext_path="$(scrubs_clean_secret_path claude-oauth-token.enc)"
if ! scrubs_has_clean_secret "${ciphertext_path}"; then
  exec "${real_claude}" "$@"
fi

claude_token="$(scrubs_decrypt_clean_secret "${ciphertext_path}" | tr -d '\r\n')"
if [ -z "${claude_token}" ]; then
  echo "scrubs claude wrapper: decrypted an empty Claude OAuth token" >&2
  exit 1
fi

# Claude already drops its own token from Bash tool commands; scrub mode adds
# defense in depth for the other credentials and processes it launches.
CLAUDE_CODE_SUBPROCESS_ENV_SCRUB="${CLAUDE_CODE_SUBPROCESS_ENV_SCRUB:-1}" \
  CLAUDE_CODE_OAUTH_TOKEN="${claude_token}" \
  exec "${real_claude}" "$@"
