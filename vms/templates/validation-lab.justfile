probe-dirty-boundary:
    test ! -e "$HOME/.local/share/scrubs/clean-auth"
    ! command -v gh >/dev/null 2>&1
    ! command -v codex >/dev/null 2>&1

probe-aube-runtime:
    ni --version >/dev/null
    node probe-aube-store.cjs
    test ! -e "$HOME/.cache/scrubs-validation-secret"
    test ! -e "$HOME/.local/share/scrubs-validation-secret"

probe-bun-runtime:
    test -d "$HOME/.bun/install/cache"
    test ! -e "$HOME/.local/share/scrubs/dirty-cache"
    grep -Fq -- '--network-concurrency=8' "$(command -v bun)"
    touch "$HOME/.bun/install/cache/.scrubs-validation-cache-bind"
    bun -e 'process.exit(0)'
