use core.nu *
use archive.nu *

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
    $a | insert $name {sql: ($tables | where name == $name | first | get sql) rows: (sql $path $"SELECT * FROM (sql-name $name)")}
  }
}
export def export-data [home: string artifact: string version: string] {
  if (exists $artifact) { fail $"Artifact exists: ($artifact)" }
  let codex = ($home | path join .codex)
  if (exists ($codex | path join config.toml)) {
    let custom = ((open ($codex | path join config.toml)).sqlite_home? | default $codex | path expand)
    if $custom != ($codex | path expand) { fail 'Custom sqlite_home is not supported by this adapter' }
  }
  mut databases = {}
  for spec in [{pattern: 'state_*.sqlite' tables: $state_tables} {pattern: 'goals_*.sqlite' tables: $goal_tables} {pattern: 'thread_history_*.sqlite' tables: $history_tables}] {
    let paths = (glob ($codex | path join $spec.pattern))
    if ($paths | length) > 1 { fail $"Multiple ($spec.pattern) databases; resolve the active version first" }
    for p in $paths { $databases = ($databases | insert ($p | path basename) (database-dump $p $spec.tables)) }
  }
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
  for thread in $threads {
    if (kind $thread.rollout_path) != file or not (under $thread.rollout_path $codex) {
      $missing = ($missing | append $"Missing or external history for ($thread.id): ($thread.rollout_path)")
      $missing_history = ($missing_history | append $thread.id)
    }
    let cwd = ($thread.cwd? | default '')
    if not ($cwd | str starts-with '/') or (kind $cwd) != dir { $missing = ($missing | append $"Unavailable workspace for ($thread.id): ($cwd)"); continue }
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
  let manifest = {format: 1 export_id: (random uuid) created_at: ((date now | into int) // 1000000000) source_home: $home codex_version: $version threads: $threads databases: $databases roots: [] git: $git_roots missing: $missing missing_history: $missing_history files: {} excluded_codex_entries: (ls -a $codex | get name | path basename | where {|p| $p not-in $chat_paths and $p !~ '^(state_|goals_|thread_history_)' })}
  temporary {|stage|
    mkdir ($stage | path join codex) ($stage | path join workspaces)
    mut m = $manifest
    for name in $chat_paths {
      let source = ($codex | path join $name)
      if (exists $source) {
        if (kind $source) == symlink { fail $"Unexpected Codex history symlink: ($source)" }
        $m.files = ($m.files | merge (snapshot $source ($stage | path join codex $name) ('codex/' + $name)))
      }
    }
    for item in ($selected | enumerate) {
      let payload = $"workspaces/($item.index)"
      $m.roots = ($m.roots | append {source: $item.item payload: $payload})
      $m.files = ($m.files | merge (snapshot $item.item ($stage | path join $payload) $payload))
    }
    for common in ($m.git | values | get common_dir | uniq) {
      let alternate = ($common | path join objects info alternates)
      if (exists $alternate) and (open --raw $alternate | str trim | is-not-empty) { $m.missing = ($m.missing | append $"External Git object alternates need consolidation: ($alternate)") }
    }
    atomic-json ($stage | path join manifest.json) $m
    # Publish without overwriting an existing artifact. COPYFILE_DISABLE avoids macOS AppleDouble entries.
    let incoming = ($stage | path join archive.tar.gz)
    with-env {COPYFILE_DISABLE: '1'} { invoke ([tar --format=pax --no-xattrs --no-acls] | append (if $nu.os-info.name == macos { [--no-fflags] } else { [] }) | append [-czf $incoming -C $stage codex workspaces manifest.json]) | ignore }
    invoke [chmod '600' $incoming] | ignore
    invoke [ln $incoming $artifact] | ignore
    {artifact: $artifact threads: ($m.threads | length) workspaces: ($selected | length) missing: $m.missing sha256: (digest $artifact)}
  }
}
