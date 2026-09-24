# Clean-side migration primitives. No project runtime or credential helpers.
export const chat_paths = [sessions archived_sessions attachments generated_images visualizations session_index.jsonl history.jsonl]
export const state_tables = [thread_sections projects project_roots threads thread_dynamic_tools thread_spawn_edges thread_artifacts]
export const goal_tables = [thread_goals thread_goal_continuation_deferrals]
export const history_tables = [thread_turns thread_items thread_history_projection_state thread_realtime_items]

export def fail [message: string] { error make {msg: $message} }
export def invoke [args: list] {
  let r = (with-env {TAR_OPTIONS: '' COPYFILE_DISABLE: '1'} { do { ^($args | first) ...($args | skip 1) } | complete })
  if $r.exit_code != 0 { fail $"Command failed: ($args | first): ($r.stderr | str trim)" }
  $r.stdout | str trim --right
}
export def exists [p: string] { ($p | path exists) or (kind $p) == 'symlink' }
export def kind [p: string] {
  try { $p | path type | default missing } catch { 'missing' }
}
export def under [p: string root: string] { $p == $root or ($p | str starts-with ($root + '/')) }
export def safe-relative [p: string] {
  $p != '' and not ($p | str starts-with '/') and not ('..' in ($p | split row '/')) and not ('.' in ($p | split row '/')) and not ('' in ($p | split row '/'))
}
export def lexical [p: string] { $p | path expand --no-symlink }
export def no-links [p: string] {
  mut cursor = (lexical $p)
  loop {
    if (kind $cursor) == symlink { fail $"Destination traverses a symlink: ($cursor)" }
    let parent = ($cursor | path dirname)
    if $parent == $cursor { break }
    $cursor = $parent
  }
}
export def digest [p: string] {
  # Canonicalize the spelling after extraction: macOS may normalize Unicode names.
  try { open --raw ($p | path expand --strict) | hash sha256 } catch {|e| fail $"Cannot hash ($p): ($e.msg)" }
}
export def mode [p: string] {
  let format = if $nu.os-info.name == macos { ['stat' '-f' '%Lp' $p] } else { ['stat' '-c' '%a' $p] }
  invoke $format | into int --radix 8
}
export def chmod-mode [p: string m: int] { invoke [chmod (($m bit-and 511) | format number | get octal | str replace '0o' '') $p] | ignore }
export def signature [p: string] {
  match (kind $p) {
    symlink => { {type: symlink target: (invoke [readlink $p])} }
    dir => { {type: directory mode: (mode $p)} }
    file => { {type: file sha256: (digest $p) mode: (mode $p)} }
    _ => { null }
  }
}
export def walk [root: string] {
  if (kind $root) != dir { return [] }
  mut paths = []
  for p in (ls -a $root | sort-by name | get name) {
    $paths = ($paths | append $p)
    if (kind $p) == dir { $paths = ($paths | append (walk $p)) }
  }
  $paths
}
export def copy [source: string target: string] {
  mkdir ($target | path dirname)
  invoke [cp -a $source $target] | ignore
}
export def atomic-json [p: string value: any] {
  mkdir ($p | path dirname)
  let temp = $p + '.' + (random uuid) + '.tmp'
  $value | to json --raw | save --raw $temp
  invoke [chmod '600' $temp] | ignore
  invoke [sync] | ignore
  mv -f $temp $p
  invoke [sync] | ignore
}
export def temporary [body: closure] {
  let p = (invoke [mktemp -d /tmp/scrubs-chats.XXXXXX] | path expand)
  try {
    let result = (do $body $p)
    invoke [chmod -R 'u+rwX' $p] | ignore
    rm -rf $p
    $result
  } catch {|e| try { invoke [chmod -R 'u+rwX' $p] | ignore; rm -rf $p }; error make $e }
}
export def process-token [pid: int] {
  let r = (do { ^ps -p ($pid | into string) -o lstart= } | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { '' }
}
export def with-lock [p: string body: closure] {
  no-links $p
  mkdir ($p | path dirname)
  let made = (do { ^mkdir -m 700 $p } | complete)
  if $made.exit_code != 0 {
    # Serialize reclamation too: a stale observation must never rename a new owner's lock.
    let claim = ($p | path join reclaim)
    let claimed = (do { ^mkdir $claim } | complete)
    if $claimed.exit_code != 0 { fail 'Another migration is checking this lock' }
    try {
      let owner = try { open ($p | path join owner.json) } catch { fail $"Migration lock owner unavailable: ($p); inspect before removing the lock" }
      if (process-token $owner.pid) == $owner.started { fail $"Another migration is running: ($p)" }
      let stale = $p + '.stale.' + (random uuid)
      invoke [mv $p $stale] | ignore
      let retry = (do { ^mkdir -m 700 $p } | complete)
      rm -rf $stale
      if $retry.exit_code != 0 { fail 'Another migration acquired the lock' }
    } catch {|e| rm -rf $claim; error make $e }
  }
  {pid: $nu.pid started: (process-token $nu.pid)} | to json | save ($p | path join owner.json)
  try { let r = (do $body); rm -rf $p; $r } catch {|e| rm -rf $p; error make $e }
}
export def sql-value [v: any] {
  match ($v | describe) {
    nothing => 'NULL'
    int => ($v | into string)
    float => ($v | into string)
    bool => (if $v { '1' } else { '0' })
    string => $"CAST\(X'($v | encode utf-8 | encode hex)' AS TEXT\)"
    binary => $"X'($v | encode hex)'"
    _ => { fail $"Unsupported SQLite value: ($v | describe)" }
  }
}
export def sql-name [v: string] { '"' + ($v | str replace --all '"' '""') + '"' }
export def sql [db: string statement: string] {
  let result = (invoke [sqlite3 -batch -bail -json $db $statement])
  if $result == '' { [] } else { $result | from json }
}
export def sql-script [db: string script: string] {
  let result = ($script | ^sqlite3 -batch -bail $db | complete)
  if $result.exit_code != 0 { fail $"SQLite failed: ($result.stderr)" }
}
export def db-backup [source: string target: string] {
  if (exists $target) { fail $"Backup exists: ($target)" }
  # SQLite's backup API includes WAL data and preserves implicit rowids too.
  # JSON quoting matches the CLI's double-quoted argument escapes, with no raw newlines.
  invoke [sqlite3 -batch -bail $source ('.backup ' + ($target | to json --raw))] | ignore
  invoke [chmod '600' $target] | ignore
}
export def initialize-db [p: string template: record] {
  sql-script $p (($template.sql | each {|r| $r + ';' } | str join "\n") + "\n" + ($template.migrations | each {|r| insert-sql '_sqlx_migrations' ($r | transpose k v | reduce -f {} {|item,a| $a | insert $item.k (if ($item.v | describe | str starts-with "record") { $item.v.hex | decode hex } else { $item.v }) }) } | str join "\n"))
}
export def insert-sql [table: string row: record] {
  $"INSERT INTO (sql-name $table) \(($row | columns | each {|k| sql-name $k } | str join ',')\) VALUES \(($row | values | each {|v| sql-value $v } | str join ',')\);"
}
export def mappings [source: string target: string pairs: list<string>] {
  mut result = [{old: ($source + '/.codex') new: ($target + '/.codex')}]
  for pair in $pairs {
    let v = ($pair | split row '=' --number 2)
    if ($v | length) != 2 or not ($v.0 | str starts-with '/') or not ($v.1 | str starts-with '/') or '..' in ($v.1 | split row '/') { fail 'Mapping requires OLD_ABSOLUTE_PATH=NEW_ABSOLUTE_PATH' }
    $result = ($result | append {old: ($v.0 | str trim --right --char '/') new: ($v.1 | str trim --right --char '/')})
  }
  $result | append {old: $source new: $target} | sort-by {|r| 0 - ($r.old | str length) }
}
export def mapped [value: string maps: list] {
  for pair in $maps {
    if (under $value $pair.old) { return ($pair.new + ($value | str substring ($pair.old | str length)..)) }
  }
  $value
}
export def transform [value: any maps: list] {
  let t = ($value | describe)
  if $t == string { mapped $value $maps } else if ($t | str starts-with 'record') {
    $value | transpose k v | reduce -f {} {|r,a| $a | insert $r.k (transform $r.v $maps) }
  } else if ($t | str starts-with 'list') or ($t | str starts-with 'table') {
    $value | each --keep-empty {|v| transform $v $maps }
  } else { $value }
}
