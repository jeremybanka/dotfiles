# Native API validation for both legacy and paginated history.
use ../chats/core.nu *
use codex-rpc.nu *

# Follow the native session filename referenced by history_base, respecting
# its exact byte cutoff. Edited prompts can retain indexed turns beyond it.
def visible-history [path: string manifest: record ancestry: list root: string --limit: int --visited: list = []] {
  if $path in $visited { fail 'Cyclic native shared-history chain' }
  let relative = ($path | path relative-to ($manifest.source_home + '/.codex'))
  let file = ($root | path join $relative)
  let key = 'codex/' + $relative
  if (digest $file) != ($manifest.files | get $key).sha256 { fail $'Retained rollout checksum mismatch: ($path)' }
  let size = (ls -D -l $file | first | get size | into int)
  let cutoff = ($limit | default $size)
  if $cutoff < 0 or $cutoff > $size { fail 'Invalid native shared-history cutoff' }
  if $cutoff == 0 { return {ids: [] bounds: []} }
  let raw = (do { ^head -c ($cutoff | into string) $file } | complete)
  if $raw.exit_code != 0 { fail 'Cannot read retained history prefix' }
  let bytes = ($raw.stdout | into binary)
  if ($bytes | bytes length) != $cutoff or ($bytes | bytes at ($cutoff - 1)..) != 0x[0a] { fail 'Native shared-history cutoff is not a complete line' }
  let events = ($bytes | decode utf-8 | lines | each { from json --strict })
  let own = ($events | where {|e| $e.type == event_msg and $e.payload.type? == task_started } | get payload.turn_id | uniq)
  let base = $events.0.payload.history_base?
  if $base == null { return {ids: $own bounds: []} }
  let candidates = ($ancestry | where {|a| ($a.path | str ends-with ('-' + $base.thread_id + '.jsonl')) or ($a.path | str ends-with ('_' + $base.thread_id + '.jsonl')) })
  if ($candidates | length) != 1 { fail 'Missing or ambiguous native retained-session file' }
  let inherited = (visible-history $candidates.0.path $manifest $ancestry $root --limit $base.end_byte_offset --visited ($visited | append $path))
  {ids: ($inherited.ids | append $own | uniq) bounds: ($inherited.bounds | append {thread_id: $base.thread_id end: $base.end_ordinal_exclusive})}
}

export def visible-turn-ids [path: string manifest: record ancestry: list root: string --limit: int] {
  (visible-history $path $manifest $ancestry $root --limit $limit).ids
}

export def check-indexed-history [tid: string turns: list history: record] {
  for t in ($history.thread_turns.rows | where thread_id == $tid) {
    let found = ($turns | where id == $t.turn_id)
    if ($found | length) != 1 { fail $'Native history missing turn: ($tid)/($t.turn_id)' }
    for item in ($history.thread_items.rows | where thread_id == $tid and turn_id == $t.turn_id) {
      if not ($found.0.items | any {|x| $x.id == $item.item_id }) { fail $'Native history missing item: ($tid)/($t.turn_id)/($item.item_id)' }
    }
  }
  {turns: ($turns | length) items: ($turns | each {|t| $t.items | length } | prepend 0 | math sum)}
}

# An edited prompt can leave an older session indexed under the stable task
# ID, while its replacement is indexed under another session ID. Native Codex
# projects the canonical rollout and supersedes the old turn. Prove both the
# retained older source files and the current visible turn/item IDs explicitly.
export def check-retained-history [expected: record turns: list history: record manifest: record ancestry: list root: string] {
  let tid = $expected.id
  let variants = ($ancestry | where {|a| $a.id? == $tid })
  if ($variants | length) < 2 { return (check-indexed-history $tid $turns $history) }
  if $root == '' { fail $'Original rollout files are required to verify retained sessions: ($tid)' }
  let streams = ($variants | each {|v|
    let relative = ($v.path | path relative-to ($manifest.source_home + '/.codex'))
    let file = ($root | path join $relative)
    let key = 'codex/' + $relative
    if (digest $file) != ($manifest.files | get $key).sha256 { fail $'Retained rollout checksum mismatch: ($v.path)' }
    let events = (open --raw $file | lines | each { from json })
    {path: $v.path base: $events.0.payload.history_base? ids: ($events | where {|e| $e.type == event_msg and $e.payload.type? == task_started } | get payload.turn_id | uniq)}
  })
  let current = ($streams | where path == $expected.rollout_path | first)
  let visible = if $current.base == null { {ids: $current.ids bounds: []} } else { visible-history $expected.rollout_path $manifest $ancestry $root }
  let current_ids = $visible.ids
  let retained_ids = ($streams.ids | flatten | uniq)
  let old = ($history.thread_turns.rows | where thread_id == $tid | get turn_id)
  if ($old | any {|id| $id not-in $retained_ids }) { fail $'Indexed turn is absent from retained histories: ($tid)' }
  if ($turns | get id | sort) != ($current_ids | sort) { fail $'Native current-session turns differ from the canonical rollout: ($tid)' }
  let indexed = ($history.thread_turns.rows | where {|r| $r.turn_id in $current_ids })
  let selected = {
    thread_turns: {rows: ($indexed | each {|r| $r | update thread_id $tid })}
    # A cutoff can supersede items within a turn that remains visible. The
    # preserved cache still contains them, but native Codex excludes them.
    thread_items: {rows: ($history.thread_items.rows | where {|r| $r.turn_id in $current_ids } | where {|r|
      not ($visible.bounds | any {|b| $b.thread_id == $r.thread_id and $r.rollout_ordinal >= $b.end })
    } | each {|r| $r | update thread_id $tid })}
  }
  (check-indexed-history $tid $turns $selected) | insert retained_superseded_turns ($old | where {|id| $id not-in $current_ids })
}

export def verify-records [instance: string manifest: record maps: list ancestry: list --checkpoint: path --rollout-root: path --codex-home: string] {
  # Verification needs identities, not another copy of every tool-result body.
  let saved = ($manifest.databases | get 'thread_history_1.sqlite')
  let history = {thread_turns: {rows: ($saved.thread_turns.rows | select thread_id turn_id)} thread_items: {rows: ($saved.thread_items.rows | select thread_id turn_id item_id rollout_ordinal)}}
  let proof = ($manifest | select source_home files)
  mut verified = []
  for batch in ($manifest.threads | chunks 10) {
    let metadata = (guest-rpc $instance ($batch | each {|t| {method: 'thread/read' params: {threadId: $t.id includeTurns: true}} }) --timeout 120sec --codex-home $codex_home | get thread)
    let paginated = ($metadata | where historyMode == paginated)
    let pages = if ($paginated | is-empty) { [] } else {
      guest-rpc $instance ($paginated | each {|t| {method: 'thread/turns/list' params: {threadId: $t.id itemsView: full limit: 100 sortDirection: asc}} }) --timeout 120sec --codex-home $codex_home
    }
    for entry in ($batch | enumerate) {
      let expected = $entry.item
      let actual = ($metadata | get $entry.index)
      if $actual.id != $expected.id or $actual.cwd != (mapped $expected.cwd $maps) or $actual.path != (mapped $expected.rollout_path $maps) { fail $'Native identity/path mismatch: ($expected.id)' }
      if ($expected.name? | is-not-empty) and $actual.name? != $expected.name { fail $'Native task name mismatch: ($expected.id)' }
      let parent = ($ancestry | where path == $expected.rollout_path | first).forked_from
      if $parent != null and $actual.forkedFromId? != $parent { fail $'Native fork ancestry mismatch: ($expected.id)' }
      mut turns = $actual.turns
      if $actual.historyMode == paginated {
        let index = ($paginated | enumerate | where {|p| $p.item.id == $actual.id } | first).index
        mut page = ($pages | get $index)
        $turns = $page.data
        mut cursors = []
        while $page.nextCursor? != null {
          let cursor = $page.nextCursor
          if $cursor in $cursors { fail $'Repeated history cursor: ($expected.id)' }
          $cursors = ($cursors | append $cursor)
          $page = (guest-rpc $instance [{method: 'thread/turns/list' params: {threadId: $expected.id itemsView: full limit: 100 sortDirection: asc cursor: $cursor}}] --timeout 120sec --codex-home $codex_home | first)
          $turns = ($turns | append $page.data)
        }
      }
      let counts = (check-retained-history $expected $turns $history $proof $ancestry ($rollout_root | default ''))
      $verified = ($verified | append ({id: $actual.id name: $actual.name? cwd: $actual.cwd forked_from: $actual.forkedFromId?} | merge $counts))
    }
    if $checkpoint != null { atomic-json (lexical $checkpoint) {verified_threads: ($verified | length) turns: ($verified.turns | math sum) threads: $verified} }
    print -e $'Verified ($verified | length)/($manifest.threads | length) histories'
  }
  {verified_threads: ($verified | length) turns: ($verified.turns | math sum) threads: $verified}
}
