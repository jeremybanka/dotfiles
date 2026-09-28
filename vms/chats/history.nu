use core.nu *

# Keep delimiters so unchanged streams remain byte-for-byte identical.
export def raw-lines [path: string] {
  let content = (open --raw $path | into binary)
  let parts = ($content | bytes split 0x[0a])
  let last_index = ($parts | length) - 1
  $parts | enumerate | each {|p|
    if $p.index < $last_index { $p.item ++ 0x[0a] } else if ($p.item | bytes length) > 0 { $p.item }
  }
}
export def rewrite-rollouts [stage: string manifest: record maps: list --preserve-malformed: record = {}] {
  let moving = ($maps | any {|m| $m.old != $m.new })
  mut streams = {}
  mut by_id = {}
  mut retained_sessions = []
  mut acknowledged = []
  for folder in [sessions archived_sessions] {
    for path in (walk ($stage | path join $folder) | where {|p| ($p | str ends-with '.jsonl') and (kind $p) == file }) {
      let key = ($path | path relative-to $stage)
      let permitted = $key in $preserve_malformed
      if $permitted and (digest $path) != ($preserve_malformed | get $key) { fail $"Malformed rollout checksum mismatch: ($key)" }
      mut before = 0
      mut after = 0
      mut boundaries = {'0': 0}
      mut result = []
      mut changed = false
      mut meta: any = null
      for line in (raw-lines $path) {
        let can_preserve = $permitted and $meta != null
        let position = $before
        let parsed = try { {value: ($line | decode utf-8 | from json --strict)} } catch {|e|
          if not $can_preserve { error make $e }
          print -e $"Preserving acknowledged malformed history bytes: ($key) at ($position)"
          {}
        }
        if 'value' not-in $parsed {
          $acknowledged = ($acknowledged | append $key | uniq)
          $before = $before + ($line | bytes length)
          $after = $after + ($line | bytes length)
          $boundaries = ($boundaries | upsert ($before | into string) $after)
          if $moving { $result = ($result | append $line) }
          continue
        }
        let value = $parsed.value
        if $meta == null { $meta = $value.payload }
        # Identity prefix maps cannot change any string. Keep JSON parsing,
        # byte accumulation, and every boundary/offset check unchanged.
        let updated = if $moving { transform $value $maps } else { $value }
        let encoded = if $value == $updated { $line } else { (($updated | to json --raw) + "\n" | encode utf-8) }
        $changed = $changed or $encoded != $line
        $before = $before + ($line | bytes length)
        $after = $after + ($encoded | bytes length)
        $boundaries = ($boundaries | upsert ($before | into string) $after)
        if $moving { $result = ($result | append $encoded) }
      }
      if $meta == null { fail $"Empty rollout: ($path)" }
      if $permitted and $changed { fail $"Acknowledged malformed history must remain byte-for-byte unchanged: ($key)" }
      $streams = ($streams | insert $key {boundaries: $boundaries changed: $changed base: $meta.history_base? id: $meta.id})
      $by_id = ($by_id | upsert $meta.id (($by_id | get -o $meta.id | default []) | append $key))
      if ($meta.session_id? | is-not-empty) {
        $by_id = ($by_id | upsert $meta.session_id (($by_id | get -o $meta.session_id | default []) | append $key | uniq))
      }
      # Native retained rollouts can keep old metadata while their filename
      # carries the session identity used by newer history_base references.
      let named = ($path | path basename | parse --regex '^rollout-.+-(?<chat>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})_(?<session>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$')
      if ($named | is-not-empty) { $retained_sessions = ($retained_sessions | append ($named.0 | insert key $key)) }
      if $changed { $result | bytes collect | save --raw -f $path }
    }
  }
  if ($acknowledged | sort) != ($preserve_malformed | columns | sort) { fail 'Malformed rollout acknowledgement must match existing malformed files exactly' }
  # A fork's rollout may begin with copied parent metadata. Its native index
  # still assigns that exact file to the fork ID; retain both associations.
  for thread in $manifest.threads {
    let key = ($thread.rollout_path | path relative-to ($manifest.source_home + '/.codex'))
    if $key not-in $streams { fail $"Missing indexed rollout: ($thread.id)" }
    let known = ($by_id | get -o $thread.id | default [])
    $by_id = ($by_id | upsert $thread.id ($known | append $key | sort | uniq))
  }
  for retained in $retained_sessions {
    if $retained.chat not-in $by_id or $retained.key not-in ($by_id | get $retained.chat) { fail 'Retained session filename does not match its indexed or metadata identity' }
    let existing = ($by_id | get -o $retained.session | default [])
    if ($existing | any {|p| $p != $retained.key }) { fail 'Ambiguous retained session identity' }
    $by_id = ($by_id | upsert $retained.session [$retained.key])
  }
  mut offsets = {}
  # Retained session IDs may own historical database rows without being active
  # sidebar threads. Resolve their offsets too; every alias must have a file.
  for identity in ($by_id | columns) {
    let key = ($by_id | get $identity | first)
    let current = ($streams | get $key)
    # Session rotation can retain several rollouts with the same task ID even
    # without history_base. Existing indexed turns may refer to an older one.
    # Reuse the strict unchanged-stream path below for all such variants.
    if $current.base == null and (($by_id | get $identity | length) == 1) {
      $offsets = ($offsets | insert $identity $current.boundaries)
      continue
    }
    mut pending = [$identity]
    mut visited = []
    mut boundaries = {}
    while ($pending | is-not-empty) {
      let tid = ($pending | first)
      $pending = ($pending | skip 1)
      if $tid in $visited { continue }
      $visited = ($visited | append $tid)
      if $tid not-in $by_id { fail $"Missing shared-history base: ($tid)" }
      for stream_key in ($by_id | get $tid) {
        let stream = ($streams | get $stream_key)
        if $stream.changed { fail $"Shared history requires unchanged rollout paths/content: ($identity); use the original home and task paths" }
        $boundaries = ($boundaries | merge $stream.boundaries)
        if $stream.base != null {
          let base = $stream.base
          if not (($by_id | get -o $base.thread_id | default []) | any {|k| ($base.end_byte_offset | into string) in ($streams | get $k | get boundaries) }) { fail $"Missing shared-history byte boundary for ($tid)" }
          $pending = ($pending | append $base.thread_id)
        }
      }
    }
    $offsets = ($offsets | insert $identity $boundaries)
  }
  $offsets
}
export def merge-pasted-index [existing: record incoming: record maps: list] {
  for index in [$existing $incoming] {
    if ($index | columns | sort) != [attachmentPaths pendingRemovalPaths textExcerptsByPath] { fail 'Unknown pasted-text index schema' }
    if ($index.pendingRemovalPaths | is-not-empty) { fail 'Pasted-text index has pending removals' }
    if not ($index.attachmentPaths | describe | str starts-with 'list') or not ($index.textExcerptsByPath | describe | str starts-with 'record') { fail 'Invalid pasted-text index' }
    for p in ($index.attachmentPaths | append ($index.textExcerptsByPath | columns)) {
      if ($p | describe) != string or not ($p | str starts-with '/') { fail 'Attachment paths must be absolute' }
    }
    if not ($index.textExcerptsByPath | values | all {|v| ($v | describe) == string }) { fail 'Invalid attachment excerpt' }
  }
  mut result = $existing
  $result.attachmentPaths = ($existing.attachmentPaths | append ($incoming.attachmentPaths | each {|p| mapped $p $maps }) | uniq)
  for item in ($incoming.textExcerptsByPath | transpose path excerpt) {
    let p = (mapped $item.path $maps)
    if $p in $result.textExcerptsByPath and ($result.textExcerptsByPath | get $p) != $item.excerpt { fail $"Attachment excerpt conflict: ($p)" }
    $result.textExcerptsByPath = ($result.textExcerptsByPath | upsert $p $item.excerpt)
  }
  $result
}
export def remap-row [original: record table: string maps: list offsets: record] {
  let moving = ($maps | any {|m| $m.old != $m.new })
  mut row = if $moving { transform $original $maps } else { $original }
  if $moving {
    for key in [item_json error_json payload metadata sandbox_policy input_schema] {
      let raw = ($row | get -o $key)
      if ($raw | describe) == string and $raw != '' {
        let parsed = try { {value: ($raw | from json)} } catch { {} }
        if 'value' in $parsed {
          let updated = (transform $parsed.value $maps)
          if $updated != $parsed.value { $row = ($row | upsert $key ($updated | to json --raw)) }
        }
      }
    }
  }
  let tid = $row.thread_id?
  if $tid != null and $tid in $offsets {
    let boundaries = ($offsets | get $tid)
    for key in [rollout_byte_offset rollout_end_byte_offset next_rollout_byte_offset] {
      let offset = ($row | get -o $key)
      if $offset != null {
        if ($offset | into string) not-in $boundaries { fail $"Unknown history byte boundary: ($table)/($tid)/($key)=($offset)" }
        $row = ($row | upsert $key ($boundaries | get ($offset | into string)))
      }
    }
  }
  if $table == thread_goals and $row.status == active { $row.status = 'paused' }
  $row
}
