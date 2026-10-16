#!/usr/bin/env nu
use chats/core.nu [fail]
use backups/core.nu *
use backups/launch-agent.nu *

# Initialize only when explicitly requested. Scheduled runs never create repositories.
def 'main init' [config_file: path] {
  let c = (config $config_file)
  prepare-state $c
  restic $c [init] | print
}
# Host-initiated run; failed sources preserve their last successful snapshot.
def 'main run' [config_file: path] {
  let report = (run-backup (config $config_file))
  print ($report | to json)
  if not $report.successful { exit 1 }
}
def 'main status' [config_file: path] { status (config $config_file) | to json }
def 'main snapshots' [config_file: path] { restic (config $config_file) [snapshots --json --tag $backup_tag] }
def 'main check' [config_file: path] { restic (config $config_file) [check --read-data] }
# Restore an inspectable migration archive; never overwrite running Codex stores.
def 'main restore' [config_file: path snapshot: string output: path] {
  restore-archive (config $config_file) $snapshot ($output | path expand --no-symlink) | to json
}
# Retention is preview-only in this draft; no scheduled deletion or pruning.
def 'main retention-preview' [config_file: path] { retention-preview (config $config_file) }
# Generate a reviewable plist without loading a scheduled job.
def 'main agent-plist' [config_file: path output: path --hour: int = 3 --minute: int = 0] {
  write-agent (config $config_file) ($output | path expand --no-symlink) --hour $hour --minute $minute | to json
}
# Install a self-contained runtime and plist. --load explicitly enables the job.
def 'main install-launch-agent' [config_file: path --hour: int = 3 --minute: int = 0 --load] {
  install-agent (config $config_file) --hour $hour --minute $minute --load=$load | to json
}
def main [] { help main }
