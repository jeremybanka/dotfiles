use ../chats/core.nu *
use ../chats/archive.nu *

export const backup_tag = 'codex-chat-backup'
const migration_cli = path self | path dirname | path join .. chats.nu

export def private-file [path: string] {
  if not ($path | str starts-with '/') { fail 'Private file paths must be absolute' }
  no-links $path
  if (kind $path) != file or ((mode $path) bit-and 63) != 0 { fail $'Expected a private file; use chmod 600: ($path)' }
}
export def config [path: path] {
  let p = (lexical $path)
  let c = (open $p)
  if $c.version? != 1 { fail 'Unsupported backup configuration version' }
  if ($c.sources? | is-empty) { fail 'Configure at least one backup source' }
  if ($c.sources.name | uniq | length) != ($c.sources | length) { fail 'Source names must be unique' }
  for s in $c.sources {
    if $s.name !~ '^[a-zA-Z0-9][a-zA-Z0-9_-]*$' { fail 'Invalid source name' }
    if $s.kind not-in [archive guest] { fail 'Source kind must be archive or guest' }
    if $s.kind == archive and not ($s.path | str starts-with '/') { fail 'Archive paths must be absolute' }
    if $s.kind == guest and $s.instance !~ '^[a-zA-Z0-9][a-zA-Z0-9_-]*$' { fail 'Invalid Lima instance name' }
  }
  if not ($c.state_dir | str starts-with '/') { fail 'state_dir must be absolute' }
  no-links $c.state_dir
  if $c.state_dir == '/' or ($c.state_dir | path expand) == ($env.HOME | path expand) { fail 'Use a dedicated state directory' }
  if not ($c.repository | str starts-with '/') and not ($c.repository | str starts-with 's3:https://') { fail 'Use an absolute local repository or s3:https:// endpoint' }
  if ($c.repository | str starts-with 's3:') and ($c.repository =~ '[@?]' or $c.repository =~ 'https://[^/]*:[^0-9/]') { fail 'Repository URLs must not contain credentials or query parameters' }
  let has_file = ($c.password_file? | is-not-empty)
  let has_command = ($c.password_command? | is-not-empty)
  if $has_file == $has_command { fail 'Configure exactly one password_file or password_command' }
  if $has_file { private-file $c.password_file }
  if $has_command {
    if ($c.password_command | describe) !~ '^list<string>' or not ($c.password_command.0 | str starts-with '/') { fail 'password_command must be an argv array with an absolute executable' }
  }
  if ($c.credentials_file? | is-not-empty) { private-file $c.credentials_file }
  if ($c.repository | str starts-with 's3:') and ($c.credentials_file? | is-empty) { fail 'S3 credentials must be explicitly configured on the host' }
  $c | insert config_path $p
}
export def prepare-state [c: record] {
  no-links $c.state_dir
  mkdir $c.state_dir
  invoke [chmod '700' $c.state_dir] | ignore
}
export def restic [c: record args: list] {
  prepare-state $c
  let password = if ($c.password_file? | is-not-empty) { open --raw $c.password_file | str trim --right } else { invoke $c.password_command }
  if $password == '' { fail 'Backup password is empty' }
  let credentials = if ($c.credentials_file? | is-empty) { {} } else { open $c.credentials_file }
  let allowed = [AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION]
  if ($credentials | columns | any {|key| $key not-in $allowed }) { fail 'Unsupported key in credentials file' }
  let backup_env = {RESTIC_PASSWORD: $password RESTIC_PASSWORD_FILE: '' RESTIC_PASSWORD_COMMAND: '' AWS_ACCESS_KEY_ID: '' AWS_SECRET_ACCESS_KEY: '' AWS_SESSION_TOKEN: '' AWS_DEFAULT_REGION: '' AWS_PROFILE: '' AWS_SHARED_CREDENTIALS_FILE: '/dev/null' AWS_CONFIG_FILE: '/dev/null' AWS_EC2_METADATA_DISABLED: 'true'} | merge $credentials
  let result = (with-env $backup_env { do { ^restic --repo $c.repository --cache-dir ($c.state_dir | path join cache) ...$args } | complete })
  # Exit 3 is a partial backup, not success. Never retain it as last_success.
  if $result.exit_code != 0 { fail $'restic failed; exit code ($result.exit_code); no successful backup recorded' }
  $result.stdout
}
export def status [c: record] {
  let p = ($c.state_dir | path join status.json)
  let identity = ($c.repository | hash sha256)
  if (exists $p) {
    let saved = (open $p)
    if $saved.repository_sha256? != $identity { fail 'State directory belongs to a different repository; use a new state_dir' }
    $saved
  } else { {version: 1 repository_sha256: $identity sources: {}} }
}
export def run-backup [c: record] {
  prepare-state $c
  with-lock ($c.state_dir | path join run.lock) {
    mut report = (status $c)
    mut failed = false
    for source in $c.sources {
      let started = (date now | format date '%+')
      let previous = ($report.sources | get -o $source.name | default {})
      let attempt = try {
        let result = (temporary {|temp|
          let archive = if $source.kind == archive { $source.path } else {
            let out = ($temp | path join source.tar.gz)
            # The existing clean guest exporter refuses active Codex writers.
            invoke [$nu.current-exe --no-config-file $migration_cli export $source.instance $out] | ignore
            $out
          }
          let payload = ($temp | path join payload)
          let manifest = (unpack $archive $payload)
          if ($manifest.missing_history? | default [] | is-not-empty) { fail 'Export reports missing task histories' }
          # Back up expanded files, so restic deduplicates history across exports.
          let output = (do { cd $temp; restic $c [backup --json --host $source.name --tag $backup_tag --tag ('source=' + $source.name) --group-by 'host,tags' payload] })
          let summary = ($output | lines | where {|line| $line | str starts-with '{' } | each { from json } | where message_type == summary | last)
          if ($summary.snapshot_id? | is-empty) { fail 'restic returned no snapshot ID' }
          {snapshot_id: $summary.snapshot_id export_id: $manifest.export_id captured_at: $manifest.created_at tasks: ($manifest.threads | length) workspace_warnings: $manifest.missing added_bytes: $summary.data_added new_data_blobs: $summary.data_blobs}
        })
        $previous | merge {last_attempt: $started last_success: (date now | format date '%+') last_result: success error: null backup: $result}
      } catch {|e|
        $previous | merge {last_attempt: $started last_result: failed error: $e.msg}
      }
      if $attempt.last_result == failed { $failed = true }
      $report.sources = ($report.sources | upsert $source.name $attempt)
      $report = ($report | upsert last_run (date now | format date '%+'))
      atomic-json ($c.state_dir | path join status.json) $report
    }
    $report | insert successful (not $failed)
  }
}
export def restore-archive [c: record snapshot: string output: string] {
  if $snapshot !~ '^[0-9a-f]{8,64}$' { fail 'Restore requires an explicit snapshot ID' }
  no-links $output
  if (exists $output) { fail 'Restore output already exists' }
  prepare-state $c
  with-lock ($c.state_dir | path join run.lock) {
    # Keep staging on the output filesystem for atomic no-clobber publication.
    let temp = (invoke [mktemp -d ($output + '.incoming.XXXXXX')])
    try {
      let snapshots = (restic $c [snapshots --json $snapshot] | from json)
      if ($snapshots | length) != 1 or $backup_tag not-in $snapshots.0.tags { fail 'Snapshot is not a Codex chat backup' }
      restic $c [restore $snapshot --target ($temp | path join restored) --verify] | ignore
      let payload = ($temp | path join restored payload)
      if (kind ($payload | path join manifest.json)) != file { fail 'Restored snapshot has no portable manifest' }
      let archive = ($temp | path join restored.tar.gz)
      with-env {COPYFILE_DISABLE: '1'} {
        invoke ([tar --format=pax --no-xattrs --no-acls] | append (if $nu.os-info.name == macos { [--no-fflags] } else { [] }) | append [-czf $archive -C $payload manifest.json codex workspaces]) | ignore
      }
      let manifest = (unpack $archive ($temp | path join verified))
      invoke [chmod '600' $archive] | ignore
      invoke [ln $archive $output] | ignore
      rm -rf $temp
      {artifact: $output snapshot_id: $snapshots.0.id tasks: ($manifest.threads | length) sha256: (digest $output)}
    } catch {|e| rm -rf $temp; error make $e }
  }
}
export def retention-preview [c: record] {
  restic $c [forget --dry-run --json --tag $backup_tag --group-by 'host,tags' --keep-daily 14 --keep-weekly 8 --keep-monthly 12]
}
