use std/assert
use ../chats/core.nu *
use ../chats/archive.nu *
use ../backups/core.nu *
use ../backups/launch-agent.nu *
use chats-fixture.nu *

const cli = path self | path dirname | path join .. chat-backups.nu

def expect-error [body: closure pattern: string] {
  let result = try { do $body | ignore; null } catch {|e| $e.msg }
  assert ($result != null and $result =~ $pattern) $'Expected error matching ($pattern), got ($result)'
}
def main [] {
  print 'Preparing synthetic chat fixture'
  temporary {|base|
    let f = (fixture $base)
    print 'Initializing encrypted test repository'
    let password = ($base | path join password)
    random uuid | save --raw $password
    invoke [chmod '600' $password] | ignore
    let cfg = ($base | path join 'config & backup.toml')
    let settings = {version: 1 repository: ($base | path join repository) state_dir: ($base | path join state) password_file: $password sources: [{name: fixture kind: archive path: $f.artifact}]}
    $settings | to toml | save $cfg
    invoke [chmod '600' $cfg] | ignore
    let c = (config $cfg)
    prepare-state $c
    restic $c [init] | ignore
    print 'Backing up fixture'
    let first = (run-backup $c)
    assert $first.successful
    assert equal $first.sources.fixture.backup.tasks 1
    let first_id = $first.sources.fixture.backup.snapshot_id
    let second = (run-backup $c)
    assert $second.successful
    assert equal $second.sources.fixture.backup.new_data_blobs 0
    assert ($second.sources.fixture.backup.added_bytes < $first.sources.fixture.backup.added_bytes)
    assert ($first_id != $second.sources.fixture.backup.snapshot_id)
    restic $c [check --read-data] | ignore
    print 'PASS encrypted backup, incremental deduplication, and repository verification'

    let archive = ($base | path join recovered.tar.gz)
    let restored = (restore-archive $c $first_id $archive)
    assert equal $restored.tasks 1
    let m = (unpack $archive ($base | path join restored))
    assert ('codex/auth.json' not-in $m.files)
    assert equal (open --raw ($base | path join restored workspaces 0 draft.txt)) "uncommitted fixture\n"
    inject ($f | update artifact $archive) | ignore
    assert equal (open --raw ($f.target | path join project draft.txt)) "uncommitted fixture\n"
    assert equal (open --raw ($f.target | path join .codex auth.json)) 'DO-NOT-EXPORT-CREDENTIAL'
    expect-error { restore-archive $c $first_id $archive } 'already exists'
    expect-error { restore-archive $c latest ($base | path join nope.tar.gz) } 'explicit snapshot'
    print 'PASS restore reconstructs a validated importable archive without credentials or overwrites'

    let previous = (status $c).sources.fixture
    let broken = ($c | update sources [{name: fixture kind: archive path: ($base | path join absent.tar.gz)} {name: healthy kind: archive path: $f.artifact}])
    let failed = (run-backup $broken)
    assert (not $failed.successful)
    assert equal $failed.sources.fixture.last_result failed
    assert equal $failed.sources.fixture.last_success $previous.last_success
    assert equal $failed.sources.fixture.backup $previous.backup
    assert equal $failed.sources.healthy.last_result success
    with-lock ($c.state_dir | path join run.lock) { expect-error { run-backup $c } 'Another migration is running' }
    print 'PASS source failures preserve last success, other sources continue, and overlapping runs refuse'

    let wrong_password = ($base | path join wrong-password)
    'wrong password' | save --raw $wrong_password
    invoke [chmod '600' $wrong_password] | ignore
    let wrong = (run-backup ($c | update password_file $wrong_password))
    assert (not $wrong.successful)
    assert equal $wrong.sources.fixture.last_success $previous.last_success
    let count = (restic $c [snapshots --json] | from json | length)
    retention-preview $c | ignore
    assert equal (restic $c [snapshots --json] | from json | length) $count
    print 'PASS wrong credentials cannot record success; retention preview never deletes'

    if $nu.os-info.name == macos {
      let plist = ($base | path join daily.plist)
      write-agent $c $plist --hour 5 --minute 17 --script '/tmp/a & b/backup.nu' | ignore
      let parsed = (invoke [plutil -convert json -o - $plist] | from json)
      assert equal $parsed.StartCalendarInterval {Hour: 5 Minute: 17}
      assert equal $parsed.ProgramArguments [$nu.current-exe --no-config-file '/tmp/a & b/backup.nu' run $cfg]
      assert equal $parsed.RunAtLoad false
      assert equal $parsed.Umask 63
      assert ('KeepAlive' not-in $parsed)
      assert ('RESTIC_PASSWORD' not-in $parsed.EnvironmentVariables)
      expect-error { agent-text $c $cli 24 0 } 'Invalid daily'
      print 'PASS daily launch agent has escaped absolute arguments, private logs, and no embedded secrets'
    }

    invoke [chmod '644' $password] | ignore
    expect-error { config $cfg } 'private file'
    invoke [chmod '600' $password] | ignore
    ($settings | update sources [{name: bad kind: archive path: relative}]) | to toml | save -f $cfg
    expect-error { config $cfg } 'absolute'
    ($settings | update sources [{name: duplicate kind: archive path: $f.artifact} {name: duplicate kind: archive path: $f.artifact}]) | to toml | save -f $cfg
    expect-error { config $cfg } 'unique'
    print 'PASS configuration rejects exposed password files, relative paths, and duplicate sources'
  }
  print 'PASS all backup integration tests'
}
