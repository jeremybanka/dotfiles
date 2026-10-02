#!/usr/bin/env nu
use std/assert
use ../chats/core.nu *
use ../chats/archive.nu *
use ../chats/schema.nu *
use ../backups/core.nu [run-backup restore-archive restic]
use codex-rpc.nu *
const vms = path self | path dirname | path dirname
const verifier = path self | path dirname | path join verify-chats-live.nu

def guest [instance: string args: list] { invoke ([limactl shell $instance --] | append $args) }

# Opt-in: an installed native Codex and clean SQLite are required. All guest
# data goes into a private temporary home; no account or model request is used.
def main [instance: string --version: string = 'codex-cli 0.159.1' --cwd: string = '/home/jem/n64-2048'] {
  assert equal (guest $instance [/run/current-system/sw/bin/codex --version]) $version
  let schema = (schema-for $version)
  let remote = (guest $instance [mktemp -d /tmp/scrubs-native-compat.XXXXXX])
  let source = ($remote | path join source)
  let target = ($remote | path join target)
  let worker = ($remote | path join tests chats-native-fixture.nu)
  let run = {|args| guest $instance ([nice -n 19 ionice -c 3 /run/current-system/sw/bin/nu --no-config-file $worker] | append $args) }
  let result = try {
    guest $instance [mkdir -p ($remote | path join tests) ($source | path join .codex) ($target | path join .codex)] | ignore
    invoke [limactl copy ($vms | path join chats-schema.json) $'($instance):($remote)/chats-schema.json'] | ignore
    invoke [limactl copy -r ($vms | path join chats) $'($instance):($remote)/chats'] | ignore
    invoke [limactl copy ($vms | path join tests chats-native-fixture.nu) $'($instance):($worker)'] | ignore
    # This starts storage initialization only; thread/start makes no model call.
    guest-rpc $instance [{method: 'thread/start' params: {cwd: $cwd approvalPolicy: never sandbox: read-only}}] --codex-home ($source | path join .codex) | ignore
    let cases = (do $run [seed $source $version $cwd] | from json)
    # Native resume materializes canonical paginated items into the history DB.
    guest-rpc $instance ($cases | where mode == paginated | each {|t| {method: 'thread/resume' params: {threadId: $t.id}} }) --codex-home ($source | path join .codex) | ignore
    let first_page = (guest-rpc $instance [{method: 'thread/turns/list' params: {threadId: $cases.0.id itemsView: full limit: 100 sortDirection: asc}}] --codex-home ($source | path join .codex) | first)
    assert equal ($first_page.data | length) 100
    assert ($first_page.nextCursor | is-not-empty)
    assert equal ($first_page.data.0.items | length) 2
    temporary {|local|
      let archive = ($local | path join native.tar.gz)
      do $run [export $source $version ($remote | path join native.tar.gz)] | ignore
      invoke [limactl copy $'($instance):($remote)/native.tar.gz' $archive] | ignore
      let manifest = (unpack $archive ($local | path join inspected))
      assert equal $manifest.scope chats
      assert equal $manifest.roots []
      assert equal ($manifest.threads | length) 3
      let saved = ($manifest.databases | get 'thread_history_1.sqlite')
      assert equal ($saved.thread_turns.rows | length) 104
      assert equal ($saved.thread_items.rows | length) 208
      assert ($saved.thread_items.rows | all {|r| $r.started_at_ms != null and $r.completed_at_ms != null })
      let password = ($local | path join password)
      random uuid | save --raw $password
      chmod-mode $password 384
      let c = {repository: ($local | path join repository) state_dir: ($local | path join state) password_file: $password sources: [{name: native kind: archive path: $archive}]}
      restic $c [init] | ignore
      let backup = (run-backup $c)
      assert $backup.successful
      restic $c [check --read-data] | ignore
      let restored = ($local | path join restored.tar.gz)
      restore-archive $c $backup.sources.native.backup.snapshot_id $restored | ignore
      invoke [limactl copy $restored $'($instance):($remote)/restored.tar.gz'] | ignore
      do $run [import $target $version ($remote | path join restored.tar.gz)] | ignore
      let report = (invoke [$nu.current-exe --no-config-file $verifier $instance $restored --destination-home $target] | from json)
      assert equal $report.verified_threads 3
      assert equal $report.turns 105
      assert equal ($report.threads.items | math sum) 210
      # Migration checksums must be accepted by native Codex on blank stores.
      let migrations = (guest $instance [sqlite3 -json ($target | path join .codex state_5.sqlite) 'SELECT version,hex(checksum) AS checksum FROM _sqlx_migrations ORDER BY version'] | from json)
      assert equal $migrations ($schema.databases.'state_5.sqlite'.migrations | each {|m| {version: $m.version checksum: $m.checksum.hex} })
      $report | reject threads | insert version $version | insert items 210 | insert encrypted_roundtrip true
    }
  } catch {|e| guest $instance [rm -rf $remote] | ignore; error make $e }
  guest $instance [rm -rf $remote] | ignore
  $result | to json
}
