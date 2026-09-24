use core.nu *

export def app-running [executable: string] {
  invoke [ps ax -o comm=] | lines | any {|line| ($line | str trim) == $executable }
}
export def migrations [plan: record] { $plan.migrations? | default [$plan] }
# Native verification is required when the desktop has only cached recent tasks.
# Copy presentation metadata from the source cache; never synthesize task history.
export def with-catalog-seeds [plan: record catalog: string verified: record] {
  mut seeds = []
  for migration in (migrations $plan) {
    for tid in $migration.thread_ids {
      let proof = ($verified.threads | where id == $tid)
      if ($proof | length) != 1 or $proof.0.cwd != $migration.cwd { fail $"Native verification does not match destination task: ($tid)" }
      let source = (sql $catalog $"SELECT * FROM local_thread_catalog WHERE host_id=(sql-value $plan.source_host) AND thread_id=(sql-value $tid)")
      if ($source | length) != 1 { fail $"Source catalog entry is missing: ($tid)" }
      mut row = ($source.0 | update host_id $plan.target_host | update cwd $migration.cwd)
      if 'display_title' in $row and $proof.0.name? != null { $row = ($row | update display_title $proof.0.name) }
      if 'missing_candidate' in $row { $row = ($row | update missing_candidate 0) }
      if 'project_id' in $row { $row = ($row | update project_id null) }
      $seeds = ($seeds | append {source: $source.0 row: $row verified: $proof.0})
    }
  }
  $plan | insert catalog_seeds $seeds
}
export def plan-changes [state: record catalog: string plan: record] {
  if $plan.source_host == $plan.target_host { fail 'Source and destination must differ' }
  mut projects = ($state | get -o 'remote-projects' | default [])
  mut assignments = ($state | get -o 'thread-project-assignments' | default {})
  mut changed = []
  mut stale = []
  mut created = []
  mut seen = []
  mut seed_rows = []
  for migration in (migrations $plan) {
    mut matches = ($projects | where id == $migration.target_project)
    if ($matches | is-empty) and ($migration.create_project? | is-not-empty) {
      let candidate = $migration.create_project
      if $candidate.id != $migration.target_project { fail 'Planned project ID mismatch' }
      if ($projects | any {|p| $p.hostId == $plan.target_host and $p.remotePath == $candidate.remotePath }) { fail 'Destination project was added since planning; prepare a fresh plan' }
      $projects = ($projects | append $candidate)
      $matches = [$candidate]
      $created = ($created | append $candidate.id)
    }
    let root = ($migration.project_root? | default $migration.cwd)
    if ($matches | length) != 1 or $matches.0.hostId != $plan.target_host or $matches.0.remotePath != $root { fail 'Destination desktop project no longer matches the plan' }
    let ids = $migration.thread_ids
    if ($ids | is-empty) or ($ids | uniq | length) != ($ids | length) or ($ids | any {|id| $id in $seen }) { fail 'Plan requires unique task IDs' }
    $seen = ($seen | append $ids)
    let desired = {projectKind: remote projectId: $migration.target_project hostId: $plan.target_host}
    for tid in $ids {
      let copies = (sql $catalog $"SELECT host_id,cwd FROM local_thread_catalog WHERE thread_id=(sql-value $tid)")
      let destination = ($copies | where host_id == $plan.target_host)
      if ($destination | is-not-empty) and $destination.0.cwd != $migration.cwd { fail $"Destination catalog path conflicts with the plan: ($tid)" }
      if ($destination | is-empty) {
        let seeds = ($plan.catalog_seeds? | default [] | where {|s| $s.row.thread_id == $tid })
        if ($seeds | length) != 1 { fail $"Destination catalog does not contain the verified task: ($tid); connect the destination in Codex first" }
        let seed = $seeds.0
        if $seed.row.host_id != $plan.target_host or $seed.row.cwd != $migration.cwd or $seed.verified.id != $tid or $seed.verified.cwd != $migration.cwd { fail 'Catalog seed does not match native verification' }
        let columns = (sql $catalog 'PRAGMA table_info(local_thread_catalog)' | get name | sort)
        if ($seed.row | columns | sort) != $columns { fail 'Catalog schema changed since planning' }
        let source = (sql $catalog $"SELECT * FROM local_thread_catalog WHERE host_id=(sql-value $plan.source_host) AND thread_id=(sql-value $tid)")
        if ($source | length) != 1 or $source.0 != $seed.source { fail $"Source catalog entry changed since planning: ($tid)" }
        $seed_rows = ($seed_rows | append $seed.row)
      }
      let previous = ($assignments | get -o $tid)
      if $previous != null and $previous != $desired {
        if $previous.hostId? != $plan.source_host or $previous.projectId? != $migration.source_project { fail $"Task has an unexpected project assignment: ($tid)" }
      }
      if $previous != $desired { $changed = ($changed | append $tid); $assignments = ($assignments | upsert $tid $desired) }
      if ($copies | any {|r| $r.host_id == $plan.source_host }) { $stale = ($stale | append $tid) }
    }
  }
  {state: ($state | upsert 'remote-projects' $projects | upsert 'thread-project-assignments' $assignments) seed_rows: $seed_rows report: {assignments_to_update: $changed source_catalog_rows_to_remove: $stale destination_catalog_rows_to_add: ($seed_rows | get -o thread_id | default []) projects_to_create: $created destination_host: $plan.target_host}}
}
export def make-plan [state: record manifest: record source_host: string target_host: string maps: list] {
  let projects = ($state | get -o 'remote-projects' | default [])
  let assignments = ($state | get -o 'thread-project-assignments' | default {})
  let sources = ($projects | where hostId == $source_host)
  let target_projects = ($projects | where hostId == $target_host)
  if ($target_projects | get remotePath | uniq | length) != ($target_projects | length) { fail 'Duplicate destination projects; resolve them before preparing' }
  mut destinations = ($target_projects | reduce -f {} {|p,a| $a | insert $p.remotePath $p })
  mut groups = []
  mut skipped = []
  for thread in $manifest.threads {
    let tid = $thread.id
    let cwd = $thread.cwd
    let source = ($thread.source? | default '')
    let archived = (($thread.archived? | default 0) == 1)
    if $archived or $source == exec or ($source | str lowercase | str contains subagent) {
      $skipped = ($skipped | append {id: $tid reason: (if $archived { 'archived' } else { 'internal or noninteractive' })}); continue
    }
    if $source not-in [cli vscode appServer] { fail $"Unknown sidebar source for ($tid): ($source)" }
    let assignment = ($assignments | get -o $tid)
    mut matches = ($sources | where {|p| $assignment != null and $p.id == $assignment.projectId? })
    if ($matches | is-empty) {
      let workspace = ($manifest.git? | default {} | get -o $cwd | default {} | get -o common_dir | default $cwd)
      $matches = ($sources | where {|p| under $workspace $p.remotePath } | sort-by {|p| 0 - ($p.remotePath | str length) })
    }
    if ($matches | is-empty) { fail $"No saved source desktop project for ($tid) \(($cwd)\)" }
    if ($matches | length) > 1 and ($matches.0.remotePath | str length) == ($matches.1.remotePath | str length) { fail $"Ambiguous source project for ($tid)" }
    let src = $matches.0
    let root = (mapped $src.remotePath $maps)
    if $root not-in $destinations { $destinations = ($destinations | insert $root {id: (random uuid) hostId: $target_host label: $src.label remotePath: $root}) }
    let dst = ($destinations | get $root)
    let mapped_cwd = (mapped $cwd $maps)
    let group_index = ($groups | enumerate | where {|g| $g.item.source_project == $src.id and $g.item.target_project == $dst.id and $g.item.cwd == $mapped_cwd } | get index)
    if ($group_index | is-empty) {
      mut g = {source_project: $src.id target_project: $dst.id project_root: $root cwd: $mapped_cwd thread_ids: [$tid]}
      if $dst.id not-in ($projects | get id) { $g = ($g | insert create_project $dst) }
      $groups = ($groups | append $g)
    } else {
      let idx = $group_index.0
      let g = ($groups | get $idx)
      $groups = ($groups | update $idx ($g | update thread_ids ($g.thread_ids | append $tid)))
    }
  }
  if ($groups | is-empty) { fail 'Archive has no active interactive tasks to assign in this desktop' }
  {format: 2 source_host: $source_host target_host: $target_host export_id: $manifest.export_id migrations: $groups archive_threads: ($manifest.threads | length) skipped_sidebar_records: $skipped}
}
export def verify-plan [plan: record] {
  let r = (plan-changes (open $plan.state_file) $plan.catalog_file $plan).report
  let pending = ($r.assignments_to_update | is-not-empty) or ($r.source_catalog_rows_to_remove | is-not-empty) or ($r.projects_to_create | is-not-empty) or ($r.destination_catalog_rows_to_add | is-not-empty)
  $r | insert verified (not $pending) | insert user_facing_tasks (migrations $plan | each {|m| $m.thread_ids | length } | math sum)
}
export def apply-plan [plan: record] {
  if (app-running $plan.app_executable) { fail 'Close Codex completely before applying this desktop repair' }
  no-links $plan.state_file
  no-links $plan.catalog_file
  let original = (open --raw $plan.state_file)
  let state = ($original | from json)
  let next = (plan-changes $state $plan.catalog_file $plan)
  if ($next.report.assignments_to_update | is-empty) and ($next.report.source_catalog_rows_to_remove | is-empty) and ($next.report.projects_to_create | is-empty) and ($next.seed_rows | is-empty) { return ($next.report | insert already_applied true) }
  let backup = $plan.backup_dir
  if (exists $backup) { fail 'Desktop backup already exists; inspect/recover the previous run' }
  invoke [mkdir -m 700 $backup] | ignore
  $original | save --raw ($backup | path join global-state.before.json)
  invoke [chmod '600' ($backup | path join global-state.before.json)] | ignore
  db-backup $plan.catalog_file ($backup | path join catalog.before.sqlite)
  let source_rows = ($next.report.source_catalog_rows_to_remove | each {|tid| sql $plan.catalog_file $"SELECT * FROM local_thread_catalog WHERE host_id=(sql-value $plan.source_host) AND thread_id=(sql-value $tid)" } | flatten)
  atomic-json ($backup | path join after-state.json) $next.state
  atomic-json ($backup | path join journal.json) {source_rows: $source_rows added_rows: $next.seed_rows}
  if (app-running $plan.app_executable) or (open --raw $plan.state_file) != $original { fail 'Desktop state changed during preparation; no repair was applied' }
  let deletes = ($next.report.source_catalog_rows_to_remove | each {|tid| $"DELETE FROM local_thread_catalog WHERE host_id=(sql-value $plan.source_host) AND thread_id=(sql-value $tid);" } | str join "\n")
  let inserts = ($next.seed_rows | each {|row| insert-sql local_thread_catalog $row } | str join "\n")
  # Cross-file atomicity uses an explicit journal; recovery restores just our rows.
  try {
    atomic-json $plan.state_file $next.state
    sql-script $plan.catalog_file ("BEGIN IMMEDIATE;\n" + $inserts + "\n" + $deletes + "\nCOMMIT;")
  } catch {|e|
    atomic-json $plan.state_file $state
    error make $e
  }
  if not (verify-plan $plan).verified { fail 'Desktop verification failed; retain journal for recovery' }
  atomic-json ($backup | path join result.json) $next.report
  $next.report | insert backup_dir $backup | insert applied true
}
export def recover-plan [plan: record] {
  if (app-running $plan.app_executable) { fail 'Close Codex completely before recovery' }
  let backup = $plan.backup_dir
  if (exists ($backup | path join result.json)) { fail 'Migration completed; recovery is only for an interrupted repair' }
  let before = (open ($backup | path join global-state.before.json))
  let after = (open ($backup | path join after-state.json))
  let current = (open $plan.state_file)
  if $current != $before and $current != $after { fail 'Desktop state changed since migration; automatic rollback refused' }
  let journal = (open ($backup | path join journal.json))
  let rows = $journal.source_rows
  let columns = (sql $plan.catalog_file 'PRAGMA table_info(local_thread_catalog)' | get name | sort)
  mut inserts = []
  for row in $rows {
    if ($row | columns | sort) != $columns { fail 'Catalog schema changed since migration' }
    let found = (sql $plan.catalog_file $"SELECT * FROM local_thread_catalog WHERE host_id=(sql-value $row.host_id) AND thread_id=(sql-value $row.thread_id)")
    if ($found | is-not-empty) and $found.0 != $row { fail 'Source catalog row changed since migration' }
    if ($found | is-empty) { $inserts = ($inserts | append (insert-sql local_thread_catalog $row)) }
  }
  mut deletes = []
  for row in ($journal.added_rows? | default []) {
    let found = (sql $plan.catalog_file $"SELECT * FROM local_thread_catalog WHERE host_id=(sql-value $row.host_id) AND thread_id=(sql-value $row.thread_id)")
    if ($found | is-not-empty) and $found.0 != $row { fail 'Added catalog row changed since migration' }
    $deletes = ($deletes | append $"DELETE FROM local_thread_catalog WHERE host_id=(sql-value $row.host_id) AND thread_id=(sql-value $row.thread_id);")
  }
  sql-script $plan.catalog_file ("BEGIN IMMEDIATE;\n" + ($inserts | append $deletes | str join "\n") + "\nCOMMIT;")
  atomic-json $plan.state_file $before
  atomic-json ($backup | path join recovery.json) {rolled_back: true}
  {rolled_back: true backup_dir: $backup}
}
