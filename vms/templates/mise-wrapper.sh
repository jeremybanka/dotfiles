#!/bin/sh
set -eu

real_mise="/run/current-system/sw/bin/mise"
refresh_script="${HOME}/.local/libexec/scrubs/install-dirty-tools.sh"

set +e
"${real_mise}" "$@"
status=$?
set -e

if [ "${status}" -eq 0 ] && [ -x "${refresh_script}" ]; then
  "${refresh_script}" >/dev/null 2>&1 || true
fi

exit "${status}"
