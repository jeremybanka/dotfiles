use core.nu *
use archive.nu *
use history.nu *

export def rollback [journal_dir: string] {
  let journal = (open ($journal_dir | path join journal.json))
  for entry in ($journal.changes | reverse) {
    no-links $entry.target
    if ($entry.backup? | is-not-empty) {
      let backup = ($journal_dir | path join $entry.backup)
      if not (safe-relative $entry.backup) or (kind $backup) != file { fail 'Invalid rollback backup' }
      copy $backup $entry.target
    } else if (exists $entry.target) { rm -rf $entry.target }
    if ($entry.database? | default false) {
      for suffix in [-wal -shm] { rm -f ($entry.target + $suffix) }
    }
  }
  rm -rf $journal_dir
}
export def recover-data [home: string] {
  let pending = (glob ($home | path join .codex scrubs-chat-imports 'pending-*'))
  mut recovered = 0
  for journal in $pending {
    if (exists ($journal | path join journal.json)) {
      if ((open ($journal | path join journal.json)).committed? | default false) { rm -rf $journal } else { rollback $journal; $recovered = $recovered + 1 }
    } else { rm -rf $journal }
  }
  {rolled_back: $recovered}
}
export def repair-git [stage: string manifest: record maps: list] {
  for root in $manifest.roots {
    for p in (walk ($stage | path join $root.payload)) {
      let type = (kind $p)
      let name = ($p | path basename)
      if $type == symlink {
        let target = (invoke [readlink $p])
        let new = (mapped $target $maps)
        if $new != $target { rm $p; invoke [ln -s -- $new $p] | ignore }
      } else if $type == file and $name in [.git gitdir] {
        let raw = (open --raw $p | str trim)
        let prefix = if ($raw | str starts-with 'gitdir: ') { 'gitdir: ' } else { '' }
        let value = ($raw | str substring ($prefix | str length)..)
        ($prefix + (mapped $value $maps) + "\n") | save --raw -f $p
      } else if $type == file and $name == config and '.git' in ($p | path split) {
        let r = (do { ^git config --file $p --get core.worktree } | complete)
        if $r.exit_code == 0 { invoke [git config --file $p core.worktree (mapped ($r.stdout | str trim) $maps)] | ignore }
      }
    }
  }
  for entry in ($manifest.files | transpose name record | sort-by {|e| 0 - ($e.name | str length) }) {
    if ($entry.name | str starts-with workspaces/) and $entry.record.type == directory { chmod-mode ($stage | path join $entry.name) $entry.record.mode }
  }
}
export def safe-destination [target: string home: string] {
  let codex = ($home | path join .codex)
  if not (under $target $home) or $target == $home or $target == $codex { fail $"Unsafe destination workspace: ($target); map inside the destination home" }
  if (under $target $codex) and not (under $target ($codex + '/worktrees')) { fail $"Workspace overlaps Codex storage: ($target)" }
  if ([($home + '/.ssh') ($home + '/.local/share/scrubs') ($home + '/.config/gh')] | any {|p| (under $target $p) or (under $p $target) }) { fail $"Workspace overlaps clean credentials: ($target)" }
  no-links $target
}
export def candidate-db [target: string candidate: string name: string tables: record schema: record maps: list offsets: record] {
  if $name not-in $schema.databases { fail $"Unsupported database: ($name)" }
  no-links $target
  if (exists $target) { db-backup $target $candidate } else { initialize-db $candidate ($schema.databases | get $name) }
  sql $candidate 'PRAGMA journal_mode=DELETE' | ignore
  let allowed = if ($name | str starts-with state_) { $state_tables } else if ($name | str starts-with goals_) { $goal_tables } else { $history_tables }
  mut statements = []
  mut inserted = 0
  for table in $allowed {
    if $table not-in $tables { continue }
    let contents = ($tables | get $table)
    let native = (sql $candidate $"SELECT sql FROM sqlite_master WHERE type='table' AND name=(sql-value $table)")
    if ($native | is-empty) or $native.0.sql != $contents.sql { fail $"Schema mismatch: ($name)/($table)" }
    let info = (sql $candidate $"PRAGMA table_info\((sql-name $table)\)")
    let keys = ($info | where pk > 0 | sort-by pk | get name)
    if ($keys | is-empty) { fail $"Missing primary key: ($table)" }
    let columns = ($info | get name | sort)
    # Build the index once. Repeated immutable record insertion copies the
    # whole history table for each row and becomes quadratic on large stores.
    let indexed = (sql $candidate $"SELECT * FROM (sql-name $table)" | each {|r|
      {key: ($r | select ...$keys | to json --raw) row: $r}
    })
    if ($indexed | is-not-empty) and (($indexed.key | sort | uniq | length) != ($indexed | length)) { fail $"Chat metadata conflict: duplicate existing keys in ($table)" }
    let existing = if ($indexed | is-empty) { {} } else { $indexed | transpose --header-row --ignore-titles --as-record }
    let incoming = ($contents.rows | each {|original|
      let row = (remap-row $original $table $maps $offsets)
      if ($row | columns | sort) != $columns { fail $"Unexpected columns: ($table)" }
      {key: ($row | select ...$keys | to json --raw) row: $row}
    } | group-by key)
    let additions = ($incoming | transpose key entries | each {|group|
      let row = $group.entries.0.row
      if ($group.entries | any {|e| $e.row != $row }) { fail $"Chat metadata conflict: ($table) ($group.key)" }
      if $group.key in $existing {
        if ($existing | get $group.key) != $row { fail $"Chat metadata conflict: ($table) ($group.key)" }
      } else { insert-sql $table $row }
    })
    $statements = ($statements | append $additions)
    $inserted = $inserted + ($additions | length)
  }
  if ($statements | is-not-empty) { sql-script $candidate ("BEGIN IMMEDIATE;\n" + ($statements | str join "\n") + "\nCOMMIT;") }
  if (sql $candidate 'PRAGMA integrity_check' | first | values | first) != ok or (sql $candidate 'PRAGMA foreign_key_check' | is-not-empty) { fail $"Database validation failed: ($name)" }
  $inserted
}
export def import-data [home: string artifact: string pairs: list<string> version: string schema: record --dry-run --allow-missing-workspaces --before-install: closure --preserve-malformed: record = {}] {
  let codex = ($home | path join .codex)
  let history = ($codex | path join scrubs-chat-imports)
  no-links $codex
  if (glob ($history | path join 'pending-*') | is-not-empty) { fail 'Interrupted import exists; run recover first' }
  temporary {|temp|
    let stage = ($temp | path join stage)
    let m = (unpack $artifact $stage)
    print -e $"Archive verified: ($m.threads | length) tasks, ($m.roots | length) workspaces"
    if ($m.missing_history? | is-not-empty) or ($m.missing | any {|x| $x | str starts-with 'Missing or external history' }) { fail 'Archive has missing conversation history; cannot import' }
    if ($m.missing | is-not-empty) and not $allow_missing_workspaces { fail $"Archive is incomplete: ($m.missing | str join '; ')" }
    if $version != $schema.codex_version or $m.codex_version != $version { fail $"Import adapter requires ($schema.codex_version) on both hosts" }
    let maps = (mappings $m.source_home $home $pairs)
    let offsets = (rewrite-rollouts ($stage | path join codex) $m $maps --preserve-malformed $preserve_malformed)
    print -e 'History paths and byte offsets verified'
    repair-git $stage $m $maps
    print -e 'Git worktree pointers prepared'
    mut changes = []
    mut evidence = {}
    for root in $m.roots {
      print -e $"Checking workspace: ($root.source)"
      let target = (mapped $root.source $maps)
      safe-destination $target $home
      let source = ($stage | path join $root.payload)
      if (exists $target) {
        if (kind $target) != dir { fail $"Workspace conflict: ($target); expected a real directory" }
        let source_paths = (['.'] | append (walk $source | each {|p| $p | path relative-to $source }) | sort)
        let target_paths = (['.'] | append (walk $target | each {|p| $p | path relative-to $target }) | sort)
        if $source_paths != $target_paths or ($source_paths | any {|p| (signature ($source | path join $p)) != (signature ($target | path join $p)) }) { fail $"Workspace conflict: ($target); use an OLD=NEW mapping to choose an empty location" }
      } else { $changes = ($changes | append {source: $source target: $target database: false}) }
      # Compute every signature from disk, but construct the large evidence
      # record only once per workspace. Sort ALL old/new keys before duplicate
      # checking so separated duplicates cannot silently overwrite evidence.
      let recorded = (walk $source | where {|p| (kind $p) != dir } | each {|p|
        {name: ($target | path join ($p | path relative-to $source)) signature: (signature $p)}
      })
      if ($recorded | is-not-empty) {
        let keys = ($evidence | columns | append $recorded.name | sort)
        if ($keys | uniq | length) != ($keys | length) { fail 'Duplicate imported file evidence' }
        $evidence = ($evidence | merge ($recorded | transpose --header-row --ignore-titles --as-record))
      }
    }
    let codex_stage = ($stage | path join codex)
    for p in (walk $codex_stage | sort) {
      if (kind $p) == dir { continue }
      let relative = ($p | path relative-to $codex_stage)
      let target = ($codex | path join $relative)
      no-links ($target | path dirname)
      let pasted_index = $relative == 'attachments/pasted-text-attachments.json'
      if $pasted_index {
        if (kind $p) == symlink or (kind $target) == symlink { fail 'Pasted-text attachment index must not be a symlink' }
        let empty = {attachmentPaths: [] pendingRemovalPaths: [] textExcerptsByPath: {}}
        let existing = if (exists $target) { open $target } else { $empty }
        atomic-json $p (merge-pasted-index $existing (open $p) $maps)
      }
      let name = ($p | path basename)
      if $name in [session_index.jsonl history.jsonl] and (exists $target) {
        if (kind $p) == symlink or (kind $target) == symlink { fail 'History index must not be a symlink' }
        let existing = (raw-lines $target)
        let incoming = (raw-lines $p | where {|line| $line not-in $existing })
        $existing | append $incoming | bytes collect | save --raw -f $p
      }
      if (signature $target) != (signature $p) {
        if (exists $target) and not $pasted_index and $name not-in [session_index.jsonl history.jsonl] { fail $"Chat file conflict: ($target)" }
        $changes = ($changes | append {source: $p target: $target database: false})
      }
      $evidence = ($evidence | insert $target (signature $p))
    }
    mut row_count = 0
    for entry in ($m.databases | transpose name tables) {
      print -e $"Preparing database: ($entry.name)"
      let target = ($codex | path join $entry.name)
      let candidate = ($temp | path join $entry.name)
      let count = (candidate-db $target $candidate $entry.name $entry.tables $schema $maps $offsets)
      if $count > 0 or not (exists $target) { $changes = ($changes | append {source: $candidate target: $target database: true}) }
      $row_count = $row_count + $count
    }
    let destinations = ($changes | each {|c| $c.target })
    if ($destinations | uniq | length) != ($destinations | length) or ($destinations | any {|a| $destinations | any {|b| $a != $b and (under $a $b) } }) { fail 'Overlapping import destinations' }
    for target in $destinations { no-links $target }
    let summary = {export_id: $m.export_id threads: ($m.threads | length) new_rows: $row_count changes: ($changes | length) dry_run: $dry_run missing_workspaces: $m.missing preserved_malformed_rollouts: $preserve_malformed workspaces: ($m.roots | each {|r| mapped $r.source $maps })}
    print -e $"Preflight complete: ($row_count) new rows, ($changes | length) file/workspace changes"
    if $dry_run or ($changes | is-empty) { return $summary }
    if $before_install != null { do $before_install }
    let journal_dir = ($history | path join ('pending-' + (random uuid)))
    mkdir $journal_dir
    mut journal = {changes: []}
    for item in ($changes | enumerate) {
      let c = $item.item
      mut entry = ($c | select target database)
      if (exists $c.target) {
        let backup = $"($item.index).backup"
        $entry = ($entry | insert backup $backup)
        if $c.database { db-backup $c.target ($journal_dir | path join $backup) } else { copy $c.target ($journal_dir | path join $backup) }
      }
      $journal.changes = ($journal.changes | append $entry)
    }
    atomic-json ($journal_dir | path join journal.json) $journal
    try {
      for c in $changes {
        if $c.database { for suffix in [-wal -shm] { rm -f ($c.target + $suffix) } }
        copy $c.source $c.target
      }
      atomic-json ($history | path join ($m.export_id + '.json')) ($summary | insert files $evidence)
      atomic-json ($journal_dir | path join journal.json) ($journal | insert committed true)
    } catch {|e| rollback $journal_dir; error make $e }
    rm -rf $journal_dir
    $summary
  }
}
