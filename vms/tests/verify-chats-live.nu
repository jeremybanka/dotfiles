#!/usr/bin/env nu
use ../chats/core.nu *
use ../chats/archive.nu *
use chats-native.nu *

# Read all imported records through native Codex, without running a model.
def main [instance: string artifact: path ...pairs: string --maintenance] {
  let home = (invoke [limactl shell $instance -- sh -lc 'printf %s "$HOME"'])
  temporary {|temp|
    let stage = ($temp | path join stage)
    let manifest = (unpack (lexical $artifact) $stage)
    let maps = (mappings $manifest.source_home $home $pairs)
    if not $maintenance {
      let paused = (do { ^limactl shell $instance -- test -e ($home + '/.codex/scrubs-migration-paused') } | complete)
      if $paused.exit_code == 0 { fail 'Guest reconnection is paused; use --maintenance for the explicit read-only check' }
    }
    let ancestry = ($manifest.files | columns | where {|p| ($p | str starts-with 'codex/sessions/') or ($p | str starts-with 'codex/archived_sessions/') } | where {|p| $p | str ends-with '.jsonl' } | each {|relative|
      let meta_path = ($stage | path join $relative)
      let meta = (open --raw $meta_path | lines | first | from json).payload
      {id: $meta.id path: ($manifest.source_home + '/.codex/' + ($relative | path relative-to codex)) forked_from: $meta.forked_from_id?}
    })
    verify-records $instance $manifest $maps $ancestry --rollout-root ($stage | path join codex)
  } | to json
}
