use core.nu *
use archive.nu [snapshot]
use history.nu *
use import.nu [candidate-db]

# Copy a fixed byte prefix. Growth after the cutoff belongs to a later backup.
# Never publish an incomplete JSONL record, even if the writer split UTF-8 bytes.
export def capture-prefix [source: string target: string --preserve-sha256: string] {
  let limit = (ls -D -l $source | first | get size | into int)
  mkdir ($target | path dirname)
  let result = (do { ^head -c ($limit | into string) $source } | complete)
  if $result.exit_code != 0 { fail $'Cannot read live history: ($source)' }
  let bytes = ($result.stdout | into binary)
  if ($bytes | bytes length) != $limit { fail $'History shrank during capture: ($source)' }
  let tail = ($bytes | bytes split 0x[0a] | last | bytes length)
  let length = $limit - $tail
  let prefix = if $length == 0 { 0x[] } else { $bytes | bytes at 0..<$length }
  let permitted = $preserve_sha256 != null
  if $permitted and ($tail != 0 or ($bytes | hash sha256) != $preserve_sha256) { fail $'Malformed rollout checksum mismatch or incomplete tail: ($source)' }
  mut malformed = false
  if $length > 0 {
    for entry in ($prefix | decode utf-8 | lines | enumerate) {
      let valid = try { $entry.item | from json --strict | ignore; true } catch { false }
      if not $valid {
        if not $permitted or $entry.index == 0 { fail $'Invalid JSON record in live history: ($source), line ($entry.index + 1)' }
        $malformed = true
      }
    }
  }
  if $permitted and not $malformed { fail $'Malformed rollout acknowledgement names a valid file: ($source)' }
  $prefix | save --raw -f $target
  chmod-mode $target (mode $source)
  {bytes: $length observed_bytes: $limit omitted_partial_bytes: $tail sha256: ($prefix | hash sha256) preserved_malformed: $permitted}
}
export def prefix-unchanged [source: string captured: record] {
  if (kind $source) != file { fail $'History disappeared during capture: ($source)' }
  if ($captured.preserved_malformed? | default false) and (ls -D -l $source | first | get size | into int) != $captured.bytes { fail $'Acknowledged malformed history changed size: ($source)' }
  let result = (do { ^head -c ($captured.bytes | into string) $source } | complete)
  if $result.exit_code != 0 or (($result.stdout | into binary | hash sha256) != $captured.sha256) { fail $'History prefix changed during capture: ($source)' }
}
export def capture-tree [source: string target: string prefix: string --preserve-malformed: record = {}] {
  mut files = {}
  mut prefixes = []
  let paths = ([$source] | append (walk $source))
  for p in $paths {
    let relative = if $p == $source { '' } else { $p | path relative-to $source }
    let key = if $relative == '' { $prefix } else { $prefix + '/' + $relative }
    let dest = if $relative == '' { $target } else { $target | path join $relative }
    if (kind $p) == file and ($p | str ends-with '.jsonl') {
      let pin = ($preserve_malformed | get -o ($key | str replace 'codex/' ''))
      let cut = (capture-prefix $p $dest --preserve-sha256 $pin)
      $files = ($files | insert $key {type: file mode: (mode $p) size: $cut.bytes sha256: $cut.sha256})
      $prefixes = ($prefixes | append ($cut | insert source $p | insert payload $key))
    } else {
      # Capture one entry, not its descendants (directories are visited below).
      if (kind $p) == dir { mkdir $dest; $files = ($files | insert $key {type: directory mode: (mode $p)}) } else {
        $files = ($files | merge (snapshot $p $dest $key))
      }
    }
  }
  {files: $files prefixes: $prefixes paths: $paths source: $source prefix: $prefix}
}
# Recheck tree membership and all copied bytes. Only captured JSONL suffixes may grow.
export def verify-tree [capture: record] {
  let paths = ([$capture.source] | append (walk $capture.source))
  if ($paths | sort) != ($capture.paths | sort) { fail $'Tree membership changed during capture: ($capture.source)' }
  for p in $paths {
    let relative = if $p == $capture.source { '' } else { $p | path relative-to $capture.source }
    let key = if $relative == '' { $capture.prefix } else { $capture.prefix + '/' + $relative }
    let expected = ($capture.files | get $key)
    let cut = ($capture.prefixes | where source == $p)
    if ($cut | is-not-empty) { prefix-unchanged $p $cut.0 } else {
      let actual = (signature $p)
      if $actual == null { fail $'File disappeared during live capture: ($p)' }
      let fields = ($actual | columns)
      if ($expected | select ...$fields) != $actual { fail $'File changed during live capture: ($p)' }
    }
  }
}
export def validate-live [stage: string manifest: record schema: record --preserve-malformed: record = {}] {
  if $manifest.codex_version != $schema.codex_version { fail $'Live capture requires adapter ($schema.codex_version)' }
  if ($manifest.missing_history | is-not-empty) { fail 'Live capture has missing indexed histories' }
  let pasted = ($stage | path join codex attachments pasted-text-attachments.json)
  if (exists $pasted) { merge-pasted-index {attachmentPaths: [] pendingRemovalPaths: [] textExcerptsByPath: {}} (open $pasted) [] | ignore }
  let offsets = (rewrite-rollouts ($stage | path join codex) $manifest [] --preserve-malformed $preserve_malformed)
  # An unassociated row cannot have its offsets proved; do not silently skip it.
  for db in ($manifest.databases | values) {
    for table in ($db | transpose name data) {
      for row in $table.data.rows {
        if $row.thread_id? != null and $row.thread_id not-in $offsets {
          fail $'Unassociated live history row: ($table.name)/($row.thread_id)'
        }
      }
    }
  }
  temporary {|validation|
    for db in ($manifest.databases | transpose name tables) {
      candidate-db ($validation | path join absent $db.name) ($validation | path join $db.name) $db.name $db.tables $schema [] $offsets | ignore
    }
  }
}
