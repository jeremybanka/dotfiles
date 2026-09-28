use core.nu *
use archive.nu *
use live.nu *
use capacity.nu *

export def codex-executable [p: string] {
  let n = ($p | path basename | str replace ' (deleted)' '' | str trim --left --char '.' | str replace --regex '-wrapped$' '')
  $n in [codex codex-code-mode-host]
}
export def quiet [] {
  if not ('/proc' | path exists) { fail 'Guest worker requires Linux /proc' }
  let busy = (ps -l | where {|p| $p.user_id? == (id -u | into int) } | where {|p| (codex-executable ($p.name? | default '')) or (codex-executable ($p.command? | default '' | split row ' ' | first)) })
  if ($busy | is-not-empty) { fail $"Close Codex connections/processes on this guest first: ($busy.pid | to json --raw)" }
}
export def database-dump [path: string allowed: list] {
  let tables = (sql $path "SELECT name,sql FROM sqlite_master WHERE type='table'")
  $allowed | where {|name| $name in $tables.name } | reduce -f {} {|name,a|
    # SQLite's SQL JSON encoder avoids the CLI formatter's very expensive
    # escaping of large saved tool results. Preserve JSON-looking TEXT as text.
    let columns = (sql $path ('PRAGMA table_info(' + (sql-name $name) + ')') | get name)
    let fields = ($columns | each {|c| [(sql-value $c) (sql-name $c)] } | flatten | str join ',')
    let query = 'SELECT json_group_array(json_object(' + $fields + ')) FROM ' + (sql-name $name)
    let rows = (invoke [sqlite3 -batch -bail -noheader -list $path $query] | from json --strict)
    $a | insert $name {sql: ($tables | where name == $name | first | get sql) rows: $rows}
  }
}
export def export-data [home: string artifact: string version: string --live --schema: record --after-databases: closure --preserve-malformed: record = {} --chats-only] {
  let started_at = ((date now | into int) // 1000000000)
  if (exists $artifact) { fail $"Artifact exists: ($artifact)" }
  let codex = ($home | path join .codex)
  if not $live and ($preserve_malformed | is-not-empty) { fail 'Malformed-history acknowledgements on export require live capture' }
  for pin in ($preserve_malformed | transpose path hash) {
    if not (safe-relative $pin.path) or $pin.path !~ '^(sessions|archived_sessions)/.+\.jsonl$' or ($pin.hash | describe) != string or $pin.hash !~ '^[0-9a-f]{64}$' { fail 'Invalid malformed-history acknowledgement' }
    if (kind ($codex | path join $pin.path)) != file { fail $'Acknowledged history does not exist: ($pin.path)' }
  }
  if (exists ($codex | path join config.toml)) {
    let custom = ((open ($codex | path join config.toml)).sqlite_home? | default $codex | path expand)
    if $custom != ($codex | path expand) { fail 'Custom sqlite_home is not supported by this adapter' }
  }
  mut databases = {}
  if $live { print -e 'Capturing online chat database snapshots' }
  let specs = [{pattern: 'state_*.sqlite' tables: $state_tables} {pattern: 'goals_*.sqlite' tables: $goal_tables} {pattern: 'thread_history_*.sqlite' tables: $history_tables}]
  # Capture identity metadata last, reducing races with newly indexed tasks.
  for spec in (if $live { $specs | reverse } else { $specs }) {
    let paths = (glob ($codex | path join $spec.pattern))
    if ($paths | length) > 1 { fail $"Multiple ($spec.pattern) databases; resolve the active version first" }
    for p in $paths {
      let contents = if $live {
        temporary {|tmp|
          let backup = ($tmp | path join snapshot.sqlite)
          try { db-backup $p $backup --existing } catch {|e| fail $'Cannot snapshot ($p): ($e.msg)' }
          if (sql $backup 'PRAGMA integrity_check' | first | values | first) != ok { fail 'Live database integrity check failed' }
          database-dump $backup $spec.tables
        }
      } else { database-dump $p $spec.tables }
      $databases = ($databases | insert ($p | path basename) $contents)
    }
  }
  if $after_databases != null { do $after_databases }
  if $live { print -e 'Chat database snapshots captured; discovering history streams' }
  mut threads = ($databases | values | each {|db| $db.threads?.rows? | default [] } | flatten)
  if ($threads | any {|t| ($t.history_mode? | default legacy) not-in [legacy paginated] }) { fail 'Unsupported Codex history_mode' }
  mut known = ($threads | each {|t| $t.id })
  for folder in [sessions archived_sessions] {
    for p in (walk ($codex | path join $folder) | where {|p| $p | str ends-with '.jsonl' }) {
      let first = (open --raw $p | lines | first | from json)
      if $first.type != session_meta or ($first.payload.id? | is-empty) { fail $"Unrecognized session file: ($p)" }
      if $first.payload.id not-in $known {
        $threads = ($threads | append {id: $first.payload.id cwd: ($first.payload.cwd? | default '') title: '(unindexed)' archived: (if $folder == archived_sessions { 1 } else { 0 }) rollout_path: $p})
        $known = ($known | append $first.payload.id)
      }
    }
  }
  mut missing = []
  mut missing_history = []
  mut roots = []
  mut registered = []
  mut git_roots = {}
  mut scanned_workspaces = []
  for thread in $threads {
    if (kind $thread.rollout_path) != file or not (under $thread.rollout_path $codex) {
      $missing = ($missing | append $"Missing or external history for ($thread.id): ($thread.rollout_path)")
      $missing_history = ($missing_history | append $thread.id)
    }
    if $chats_only { continue }
    let cwd = ($thread.cwd? | default '')
    if not ($cwd | str starts-with '/') or (kind $cwd) != dir { $missing = ($missing | append $"Unavailable workspace for ($thread.id): ($cwd)"); continue }
    # A consolidated guest can have hundreds of chats in the same project.
    # Discover its Git worktrees and status once per capture attempt.
    if $cwd in $scanned_workspaces { continue }
    $scanned_workspaces = ($scanned_workspaces | append $cwd)
    let git = try {
      let top = (invoke [git -C $cwd rev-parse --show-toplevel])
      let common = (invoke [git -C $cwd rev-parse --path-format=absolute --git-common-dir])
      {top: $top common: $common worktrees: (invoke [git -C $cwd worktree list --porcelain] | lines | where {|l| $l | str starts-with 'worktree ' } | each {|l| $l | str substring 9.. }) head: (invoke [git -C $top rev-parse HEAD]) status: (invoke [git -C $top status --porcelain=v1])}
    } catch { null }
    if $git == null { $roots = ($roots | append $cwd); continue }
    for p in $git.worktrees {
      if (kind $p) == dir { $roots = ($roots | append $p); $registered = ($registered | append ($p | path expand)) } else { $missing = ($missing | append $"Unavailable Git worktree: ($p)") }
    }
    $roots = ($roots | append $git.common)
    $git_roots = ($git_roots | upsert $git.top {common_dir: $git.common head: $git.head status: $git.status})
  }
  mut safe = []
  for root in ($roots | uniq) {
    let p = ($root | path expand)
    if $p == $home or $p == $codex or (under $home $p) or ((under $p $codex) and not (under $p ($codex + '/worktrees'))) {
      $missing = ($missing | append $"Broad or protected workspace omitted: ($p)"); continue
    }
    let protected = [($home + '/.ssh') ($home + '/.local/share/scrubs') ($home + '/.config/gh')]
    let owner = (ls -D -l $p | first | get user)
    let temp_worktree = $p in $registered and ($owner == (invoke [id -un]) or ($owner | into string) == (invoke [id -u])) and ([('/tmp' | path expand) ('/var/tmp' | path expand)] | any {|q| $p != $q and (under $p $q) })
    if (not (under $p $home) and not $temp_worktree) or ($protected | any {|q| (under $p $q) or (under $q $p) }) {
      $missing = ($missing | append $"Workspace outside the permitted home/project scope omitted: ($p)"); continue
    }
    $safe = ($safe | append $p)
  }
  let selected = ($safe | uniq | where {|p| not ($safe | any {|q| $p != $q and (under $p $q) }) } | sort)
  let manifest = {format: 1 scope: (if $chats_only { 'chats' } else { 'chats-and-workspaces' }) export_id: (random uuid) created_at: ((date now | into int) // 1000000000) source_home: $home codex_version: $version threads: $threads databases: $databases roots: [] git: $git_roots missing: $missing missing_history: $missing_history files: {} excluded_codex_entries: (ls -a $codex | get name | path basename | where {|p| $p not-in $chat_paths and $p !~ '^(state_|goals_|thread_history_)' })}
  temporary {|stage|
    if $live {
      let sources = ($chat_paths | each {|p| $codex | path join $p } | where {|p| exists $p } | append $selected)
      let payload = (path-bytes ($sources | each {|p| [$p] | append (walk $p) } | flatten))
      require-space (free-bytes $stage) $payload | ignore
    }
    mkdir ($stage | path join codex) ($stage | path join workspaces)
    if $live { print -e 'Capturing chat payload and verifying unchanged prefixes' }
    mut m = $manifest
    mut captures = []
    for name in $chat_paths {
      let source = ($codex | path join $name)
      if (exists $source) {
        if (kind $source) == symlink { fail $"Unexpected Codex history symlink: ($source)" }
        if $live {
          let captured = (capture-tree $source ($stage | path join codex $name) ('codex/' + $name) --preserve-malformed $preserve_malformed)
          $m.files = ($m.files | merge $captured.files)
          $captures = ($captures | append $captured)
        } else { $m.files = ($m.files | merge (snapshot $source ($stage | path join codex $name) ('codex/' + $name))) }
      }
    }
    for item in ($selected | enumerate) {
      let payload = $"workspaces/($item.index)"
      $m.roots = ($m.roots | append {source: $item.item payload: $payload})
      let paths = if $live { [$item.item] | append (walk $item.item) } else { [] }
      let files = (snapshot $item.item ($stage | path join $payload) $payload)
      $m.files = ($m.files | merge $files)
      if $live { $captures = ($captures | append {source: $item.item prefix: $payload paths: $paths files: $files prefixes: []}) }
    }
    for common in ($m.git | values | get common_dir | uniq) {
      let alternate = ($common | path join objects info alternates)
      if (exists $alternate) and (open --raw $alternate | str trim | is-not-empty) { $m.missing = ($m.missing | append $"External Git object alternates need consolidation: ($alternate)") }
    }
    if $live {
      if $schema == null { fail 'Live capture requires a schema adapter' }
      for captured in $captures { verify-tree $captured }
      print -e 'Validating captured history relationships and database candidates'
      validate-live $stage $m $schema --preserve-malformed $preserve_malformed
      $m = ($m | insert capture {mode: live consistency: 'validated-prefixes-and-per-database-snapshots' started_at: $started_at finished_at: ((date now | into int) // 1000000000) history_prefixes: ($captures | each {|c| $c.prefixes } | flatten) preserved_malformed_rollouts: $preserve_malformed})
    }
    # Staging is disposable; do not flush the active guest's entire filesystem.
    atomic-json ($stage | path join manifest.json) $m --transient
    # Publish without overwriting an existing artifact. COPYFILE_DISABLE avoids macOS AppleDouble entries.
    let incoming = ($stage | path join archive.tar.gz)
    if $live { print -e 'Validation passed; compressing the chat archive' }
    with-env {COPYFILE_DISABLE: '1'} { invoke ([tar --format=pax --no-xattrs --no-acls] | append (if $nu.os-info.name == macos { [--no-fflags] } else { [] }) | append [-czf $incoming -C $stage codex workspaces manifest.json]) | ignore }
    invoke [chmod '600' $incoming] | ignore
    invoke [ln $incoming $artifact] | ignore
    {artifact: $artifact threads: ($m.threads | length) workspaces: ($selected | length) missing: $m.missing sha256: (digest $artifact)}
  }
}

# Bounded retry of a complete attempt. No partial artifact is published.
export def export-live [home: string artifact: string version: string schema: record --attempts: int = 3 --after-databases: closure --preserve-malformed: record = {} --chats-only] {
  if $attempts < 1 or $attempts > 10 { fail 'Live capture attempts must be between 1 and 10' }
  if $version != $schema.codex_version { fail $'Live capture requires adapter ($schema.codex_version)' }
  mut errors = []
  for attempt in 1..$attempts {
    let outcome = try { {result: (export-data $home $artifact $version --live --schema $schema --after-databases $after_databases --preserve-malformed $preserve_malformed --chats-only=$chats_only)} } catch {|e| {error: ($e.rendered? | default $e.msg)} }
    if 'result' in $outcome { return ($outcome.result | insert attempts $attempt | insert capture_mode live) }
    $errors = ($errors | append $outcome.error)
    if $attempt < $attempts { sleep 100ms }
  }
  fail $'Live capture did not stabilize after ($attempts) attempts: ($errors | last)'
}
