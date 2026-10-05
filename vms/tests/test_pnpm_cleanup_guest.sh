#!/bin/bash
# Run in a bootstrapped guest with mise-managed pnpm 12.8.1 and Node 26.10.0.
# No registry requests or changes to existing projects are needed.
set -euo pipefail
helper="$(cd "$(dirname "$0")/../templates" && pwd)/prune-pnpm-stores.sh"
lab="$(mktemp -d /tmp/scrubs-pnpm-prune.XXXXXX)"
trap 'rm -rf "$lab"' EXIT
project="$lab/project"
mkdir -p "$project/vendor/package"
printf '%s\n' '{"name":"scrubs-prune-fixture","version":"1.0.0","main":"index.js"}' > "$project/vendor/package/package.json"
printf '%s\n' 'module.exports = 42' > "$project/vendor/package/index.js"
tar -czf "$project/fixture.tgz" -C "$project/vendor" package
printf '%s\n' '{"name":"scrubs-prune-test","version":"1.0.0","dependencies":{"scrubs-prune-fixture":"file:./fixture.tgz"}}' > "$project/package.json"
printf '%s\n' '[tools]' 'pnpm = "12.8.1"' 'node = "26.10.0"' > "$project/mise.toml"
printf '%s\n' 'storeDir: ./decoy-store' 'enableGlobalVirtualStore: false' > "$project/pnpm-workspace.yaml"
mkdir "$project/decoy-store"
touch "$project/decoy-store/keep"
/run/current-system/sw/bin/git -C "$project" init -q
cd "$project"
/run/current-system/sw/bin/mise trust --quiet
proxy="$HOME/.local/bin/scrubs-dirty-exec"
legacy="$project/.pnpm-store"
current="$project/node_modules/.pnpm-store"
"$proxy" pnpm --store-dir "$legacy" install --offline --ignore-scripts
rm -rf "$project/node_modules"
"$proxy" pnpm --store-dir "$current" install --offline --ignore-scripts
# Give the legacy store a valid content-addressed file with no installation link.
hash="$(printf 'unreferenced fixture\n' | sha512sum | cut -d ' ' -f 1)"
blob="$legacy/v11/files/${hash:0:2}/${hash:2}"
mkdir -p "$(dirname "$blob")"
printf 'unreferenced fixture\n' > "$blob"

source "$helper"
log() { printf '%s %s\n' "$1" "$2"; }
size_of() { du -sh "$1" | cut -f 1; }
# This fixture is isolated from existing stores. Active-process behavior is
# tested separately without stopping another user's guest work.
dirty_space_active() { return 1; }
FREE_DRY_RUN=1
scrubs_prune_pnpm_stores "$lab"
test -f "$blob"
FREE_DRY_RUN=0
scrubs_prune_pnpm_stores "$lab"
test ! -e "$blob"
test -f "$project/decoy-store/keep"
"$proxy" node -e 'const fs=require("fs"); if(require("scrubs-prune-fixture")!==42)process.exit(1); for(const p of [process.env.HOME+"/.codex",process.env.HOME+"/.local/share/scrubs/clean-auth",process.env.HOME+"/.local/share/pnpm/store"])if(fs.existsSync(p))throw Error("clean path visible: "+p)'
printf 'PASS: exact legacy and nested stores pruned, installed dependency works, decoy and clean boundary preserved\n'
