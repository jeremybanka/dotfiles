use std/assert
use ../chats/core.nu *
use ../chats/archive.nu *
use ../chats/export.nu *
use ../chats/live.nu *
use ../chats/import.nu [import-data]
use chats-fixture.nu *
use ../chats/schema.nu *
const writer = path self | path dirname | path join chats-live-writer.nu

def rejects [body: closure pattern: string] {
  let message = try { do $body | ignore; null } catch {|e| $e.msg }
  assert ($message != null and $message =~ $pattern) $'Expected ($pattern), got ($message)'
}
def main [--version: string = 'codex-cli 0.154.0'] {
  temporary {|base|
    let f = (fixture $base --schema (schema-for $version))
    if $version == 'codex-cli 0.157.0' {
      sql-script ($f.source | path join .codex state_5.sqlite) $"UPDATE threads SET creator_user_id='synthetic-user',creator_account_id='synthetic-account'; INSERT INTO thread_attachments VALUES \('attachment', '($f.tid)', 'file', 'fixture', '{}', 1\);"
    }
    let original = (open --raw $f.rollout | into binary)
    # An incomplete Unicode codepoint must be preserved on the source and
    # omitted only beyond the recorded complete-line cutoff.
    ($original ++ 0x[7b22 c3]) | save --raw -f $f.rollout
    let cut = (capture-prefix $f.rollout ($base | path join prefix))
    assert equal $cut.omitted_partial_bytes 3
    assert equal (open --raw ($base | path join prefix) | into binary) $original
    prefix-unchanged $f.rollout $cut
    ('{"type":"event_msg"}' + "\n") | save --raw --append $f.rollout
    prefix-unchanged $f.rollout $cut
    'overwritten' | save --raw -f $f.rollout
    rejects { prefix-unchanged $f.rollout $cut } 'prefix changed'
    $original | save --raw -f $f.rollout
    print 'PASS complete-byte prefixes handle partial UTF-8, growth, and rewrites'

    let malformed = ($base | path join malformed.jsonl)
    "{\"valid\":true}\nPRIVATE-MALFORMED-CONTENT\n" | save --raw $malformed
    let message = try { capture-prefix $malformed ($base | path join malformed-copy) | ignore; '' } catch {|e| $e.msg }
    assert ($message =~ 'Invalid JSON record in live history:' and $message =~ 'line 2')
    assert (not ($message | str contains 'PRIVATE-MALFORMED-CONTENT'))
    assert (not (exists ($base | path join malformed-copy)))
    print 'PASS malformed history reports its location without exposing chat content'

    # Exercise closed WAL stores as well as the active writer below.
    sql ($f.source | path join .codex state_5.sqlite) 'PRAGMA journal_mode=WAL' | ignore
    let artifact = ($base | path join live.tar.gz)
    let result = (export-live $f.source $artifact $f.schema.codex_version $f.schema)
    assert equal $result.capture_mode live
    let m = (unpack $artifact ($base | path join unpacked))
    assert equal $m.capture.mode live
    assert equal $m.files.'codex/sessions/fixture.jsonl'.sha256 ($original | hash sha256)
    inject ($f | update artifact $artifact) | ignore
    if $version == 'codex-cli 0.157.0' {
      assert equal (sql ($f.target | path join .codex state_5.sqlite) 'SELECT creator_user_id FROM threads').0.creator_user_id synthetic-user
      assert equal (sql ($f.target | path join .codex state_5.sqlite) 'SELECT id FROM thread_attachments').0.id attachment
    }
    assert equal (open --raw ($f.target | path join project draft.txt)) "uncommitted fixture\n"
    print 'PASS live archive validates and imports histories and unfinished workspace files'
    let absent_db = ($base | path join vanished.sqlite)
    rejects { db-backup $absent_db ($base | path join absent-copy.sqlite) --existing } 'unable to open'
    assert (not (exists $absent_db))

    let ahead = ($f.source | path join .codex thread_history_1.sqlite)
    sql-script $ahead "UPDATE thread_history_projection_state SET next_rollout_byte_offset=999999"
    let refused = ($base | path join refused.tar.gz)
    rejects { export-live $f.source $refused $f.schema.codex_version $f.schema --attempts 2 } 'Unknown history byte boundary'
    assert (not (exists $refused))
    sql-script $ahead $'UPDATE thread_history_projection_state SET next_rollout_byte_offset=($original | bytes length)'
    print 'PASS incompatible history cutoffs exhaust bounded retries without publication'

    let marker = ($base | path join retried)
    let retried = (export-live $f.source ($base | path join retry.tar.gz) $f.schema.codex_version $f.schema --after-databases {
      if not (exists $marker) {
        '1' | save $marker
        "bad JSON\n" | save --raw --append $f.rollout
      } else { $original | save --raw -f $f.rollout }
    })
    assert equal $retried.attempts 2
    print 'PASS a transient torn/replaced history retries the entire capture'

    let tree = ($base | path join stable-tree)
    mkdir $tree
    'before' | save ($tree | path join file)
    let captured = (capture-tree $tree ($base | path join tree-copy) test)
    'after' | save -f ($tree | path join file)
    rejects { verify-tree $captured } 'File changed'
    'new' | save ($tree | path join new-file)
    rejects { verify-tree $captured } 'membership changed'
    print 'PASS workspace edits and new files invalidate the capture'

    {rollout: $f.rollout database: ($f.source | path join .codex state_5.sqlite) thread: $f.tid} | to json | save ($base | path join writer.json)
    let pid = (invoke [sh -c '"$1" --no-config-file "$2" "$3" >"$3/writer.log" 2>&1 & echo $!' writer $nu.current-exe $writer $base] | into int)
    try {
      mut polls = 0
      while not (exists ($base | path join count)) {
        if $polls > 100 { fail $'Synthetic writer did not start: (open --raw ($base | path join writer.log))' }
        sleep 20ms
        $polls = $polls + 1
      }
      let before = (open --raw ($base | path join count) | into int)
      let concurrent = ($base | path join concurrent.tar.gz)
      export-live $f.source $concurrent $f.schema.codex_version $f.schema | ignore
      let after = (open --raw ($base | path join count) | into int)
      assert ($after > $before)
      let snap = (unpack $concurrent ($base | path join concurrent))
      assert equal $snap.capture.mode live
      assert ($snap.files.'codex/sessions/fixture.jsonl'.size > ($original | bytes length))
      let restored_home = ($base | path join concurrent-restored)
      mkdir ($restored_home | path join .codex)
      import-data $restored_home $concurrent [] $version $f.schema | ignore
      assert equal (open --raw ($restored_home | path join project draft.txt)) "uncommitted fixture\n"
      'stop' | save ($base | path join stop)
      print 'PASS capture and restore complete while a separate writer appends history and commits WAL updates'
    } catch {|e| 'stop' | save -f ($base | path join stop); error make $e }
    # Wait for our writer to notice its stop file before fixture cleanup.
    sleep 200ms
  }
  print 'PASS all live capture tests'
}
