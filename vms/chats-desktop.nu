#!/usr/bin/env nu
use chats/core.nu *
use chats/archive.nu *
use chats/desktop.nu *
const script = path self

def companion [plan: string suffix: string] { ($plan | path parse | update extension $suffix | path join) }
def lock-path [plan: record] { $plan.state_file | path dirname | path join .scrubs-desktop-migration.nu-lock }
def batch-plans [batch: path] {
  let paths = (open $batch)
  if ($paths | is-empty) or not ($paths | all {|p| ($p | describe) == string and ($p | str starts-with '/') }) { fail 'Batch must contain absolute plan filenames' }
  let plans = ($paths | each {|p| open $p })
  for field in [state_file catalog_file app_executable app_bundle] {
    if ($plans | get $field | uniq | length) != 1 { fail $"Batch plans must share ($field)" }
  }
  if ($plans.backup_dir | uniq | length) != ($plans | length) { fail 'Batch backup paths must be distinct' }
  let ids = ($plans | each {|p| migrations $p | get thread_ids | flatten } | flatten)
  if ($ids | uniq | length) != ($ids | length) { fail 'Batch task IDs must be distinct' }
  $plans
}
# Apply several source-host plans while holding one lock and reopen only once.
def 'main apply-batch' [batch: path --wait-for-exit: int = 0 --reopen] {
  let plans = (batch-plans $batch)
  if $wait_for_exit < 0 { fail 'Wait timeout cannot be negative' }
  with-lock (lock-path $plans.0) {
    if $wait_for_exit > 0 {
      print 'Waiting for Codex to close. Nothing has been changed yet.'
      let deadline = (date now) + ($wait_for_exit * 1sec)
      while (app-running $plans.0.app_executable) {
        if (date now) >= $deadline { fail 'Timed out without changing desktop state' }
        sleep 1sec
      }
      sleep 4sec
    }
    # Preflight the cumulative state before the first write.
    mut state = (open $plans.0.state_file)
    for p in $plans { $state = (plan-changes $state $p.catalog_file $p).state }
    for p in $plans { print (apply-plan $p | to json) }
    if $reopen { invoke [open $plans.0.app_bundle] | ignore }
  }
}
# A batch is a JSON array of absolute plan filenames.
def 'main arm-batch' [batch: path --wait-for-exit: int = 900 --reopen] {
  if $wait_for_exit <= 0 { fail 'arm-batch requires a positive wait timeout' }
  let path = (lexical $batch)
  let plans = (batch-plans $path)
  let reports = ($plans | each {|p| verify-plan $p })
  if ($reports | all {|r| $r.verified }) { return ({already_applied: true reports: $reports} | to json) }
  if $nu.os-info.name != macos { fail 'Desktop arming requires macOS launchd' }
  let log = (companion $path worker.log)
  if (exists $log) { fail $"Worker log already exists: ($log)" }
  '' | save --raw $log
  invoke [chmod '600' $log] | ignore
  let label = 'com.jeremybanka.scrubs-chat-repair.' + (random uuid)
  let flags = if $reopen { [--reopen] } else { [] }
  invoke ([launchctl submit -l $label -o $log -e $log -- /bin/sh -c 'label=$1; shift; "$@"; result=$?; /bin/launchctl remove "$label"; exit "$result"' scrubs-worker $label $nu.current-exe --no-config-file $script apply-batch $path --wait-for-exit ($wait_for_exit | into string)] | append $flags) | ignore
  {job: $label log: $log plans: ($plans | length) quit_within_seconds: $wait_for_exit} | to json
}
# Prepare a sidebar ownership plan after verifying import and connecting the target.
def 'main prepare' [artifact: path source: string target: string out: path ...maps: string --codex-home: path --catalog: path --app-bundle: path --native-report: path] {
  let home = ($codex_home | default ($env.HOME | path join .codex) | path expand)
  let state_file = ($home | path join .codex-global-state.json)
  let candidates = (glob ($home | path join sqlite 'codex*.db') | where {|p| sql $p "SELECT 1 FROM sqlite_master WHERE name='local_thread_catalog'" | is-not-empty })
  let db = if $catalog != null { lexical $catalog } else if ($candidates | length) == 1 { $candidates.0 } else { fail 'Cannot select a unique desktop catalog; supply --catalog' }
  let bundles = (['/Applications/ChatGPT.app' '/Applications/Codex.app'] | where {|p| exists $p })
  let bundle = if $app_bundle != null { lexical $app_bundle } else if ($bundles | length) == 1 { $bundles.0 } else { fail 'Cannot select a unique application; supply --app-bundle' }
  let executable_name = (invoke [plutil -extract CFBundleExecutable raw -o - ($bundle | path join Contents Info.plist)])
  let executable = ($bundle | path join Contents MacOS $executable_name)
  if (kind $executable) != file { fail 'Application executable is missing' }
  let source_host = if ($source | str contains ':') { $source } else { 'remote-ssh-discovered:lima-' + $source }
  let target_host = if ($target | str contains ':') { $target } else { 'remote-ssh-discovered:lima-' + $target }
  let pairs = (mappings '/__no_source_home__' '/__no_source_home__' $maps)
  let archive = (lexical $artifact)
  let output = (lexical $out)
  let plan = (temporary {|temp| make-plan (open $state_file) (unpack $archive ($temp | path join stage)) $source_host $target_host $pairs }) | merge {state_file: $state_file catalog_file: $db app_bundle: $bundle app_executable: $executable backup_dir: (companion $output backup) artifact: $archive artifact_sha256: (digest $archive)}
  let verified_plan = if $native_report == null { $plan } else { with-catalog-seeds $plan $db (open $native_report) }
  let report = (verify-plan $verified_plan)
  $verified_plan | to json | save $output
  invoke [chmod '600' $output] | ignore
  $report | insert plan $output | insert skipped_sidebar_records $plan.skipped_sidebar_records | to json
}
def 'main preview' [plan: path] { verify-plan (open $plan) | to json }
def 'main verify' [plan: path] {
  let report = (verify-plan (open $plan))
  print ($report | to json)
  if not $report.verified { exit 1 }
}
def 'main recover' [plan: path] {
  let p = (open $plan)
  with-lock (lock-path $p) { recover-plan $p } | to json
}
# Wait for app exit, apply the backed-up repair, optionally reopen the app.
def 'main apply' [plan: path --wait-for-exit: int = 0 --reopen] {
  let p = (open $plan)
  if $wait_for_exit < 0 { fail 'Wait timeout cannot be negative' }
  with-lock (lock-path $p) {
    if $wait_for_exit > 0 {
      print 'Waiting for Codex to close. Nothing has been changed yet.'
      let deadline = (date now) + ($wait_for_exit * 1sec)
      while (app-running $p.app_executable) {
        if (date now) >= $deadline { fail 'Timed out without changing desktop state' }
        sleep 1sec
      }
      sleep 4sec
    }
    print (apply-plan $p | to json)
    if $reopen { invoke [open $p.app_bundle] | ignore }
  }
}
# Detach a worker that survives the current shell and waits for Codex to quit.
def 'main arm' [plan: path --wait-for-exit: int = 900 --reopen] {
  if $wait_for_exit <= 0 { fail 'arm requires a positive wait timeout' }
  let path = (lexical $plan)
  let p = (open $path)
  let report = (verify-plan $p)
  if $report.verified { return ($report | insert already_applied true | to json) }
  let log = (companion $path worker.log)
  if (exists $log) { fail $"Worker log already exists: ($log); inspect before rearming" }
  if $nu.os-info.name != macos { fail 'Desktop arming requires macOS launchd' }
  let flags = if $reopen { [--reopen] } else { [] }
  '' | save --raw $log
  invoke [chmod '600' $log] | ignore
  let label = 'com.jeremybanka.scrubs-chat-repair.' + (random uuid)
  # launchd owns the process, so quitting Codex cannot kill its child tree.
  # The fixed shell bridge removes the transient job after Nu exits, even on error.
  invoke ([launchctl submit -l $label -o $log -e $log -- /bin/sh -c 'label=$1; shift; "$@"; result=$?; /bin/launchctl remove "$label"; exit "$result"' scrubs-worker $label $nu.current-exe --no-config-file $script apply $path --wait-for-exit ($wait_for_exit | into string)] | append $flags) | ignore
  sleep 300ms
  let job = (invoke [launchctl list $label])
  let pid = ($job | parse --regex '"PID" = (?<pid>[0-9]+);' | get -o 0.pid)
  {job: $label pid: $pid log: $log quit_within_seconds: $wait_for_exit} | to json
}
def main [] { help main }
