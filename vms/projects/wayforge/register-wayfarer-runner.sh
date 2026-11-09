#!/usr/bin/env bash
set -euo pipefail

# Only the short-lived repository registration token crosses into the guest.
# No PAT is stored in the VM, the Nix store, or this repository.
gh api --method POST repos/jeremybanka/wayfarer/actions/runners/registration-token --jq .token \
  | limactl shell wayforge -- sudo sh -c '
      set -eu
      install -d -m 0700 /var/lib/wayfarer-ci-secrets
      umask 077
      token_tmp=$(mktemp /var/lib/wayfarer-ci-secrets/registration-token.XXXXXX)
      cleanup() { rm -f -- "$token_tmp"; }
      trap cleanup EXIT
      tr -d "\n" > "$token_tmp"
      test -s "$token_tmp"
      mv -f "$token_tmp" /var/lib/wayfarer-ci-secrets/registration-token
    '

limactl shell wayforge -- sudo systemctl restart github-runner-wayfarer.service
