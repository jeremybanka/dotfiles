use std/assert
use ../chats/core.nu *
use ../chats/live.nu *
use ../chats/export.nu *
use ../chats/archive.nu *
use ../chats/import.nu [import-data]
use ../chats/capacity.nu *
use ../backups/core.nu [run-backup restore-archive restic]
use chats-fixture.nu *

def rejects [body: closure pattern: string] {
  let message = try { do $body | ignore; '' } catch {|e| $e.rendered? | default $e.msg }
  assert ($message =~ $pattern) $'Expected ($pattern), got ($message)'
}
def main [] {
  temporary {|base|
    let f = (fixture $base)
    let meta = ({type: session_meta payload: {id: $f.tid}} | to json --raw)
    let damaged = (($meta + "\n") | encode utf-8) ++ 0x[0000000a]
    $damaged | save --raw -f $f.rollout
    sql-script ($f.source | path join .codex thread_history_1.sqlite) $'UPDATE thread_history_projection_state SET next_rollout_byte_offset=($damaged | bytes length)'
    let key = ($f.rollout | path relative-to ($f.source | path join .codex))
    let pin = (digest $f.rollout)
    let acknowledgement = ({} | insert $key $pin)
    let cut = (capture-prefix $f.rollout ($base | path join preserved) --preserve-sha256 $pin)
    assert $cut.preserved_malformed
    assert equal (digest ($base | path join preserved)) $pin
    rejects { capture-prefix $f.rollout ($base | path join refused) } 'Invalid JSON record'
    rejects { capture-prefix $f.rollout ($base | path join refused) --preserve-sha256 ('0' | fill --width 64 --character '0') } 'checksum mismatch'
    "{}\n" | save --raw --append $f.rollout
    rejects { prefix-unchanged $f.rollout $cut } 'changed size'
    rejects { capture-prefix $f.rollout ($base | path join refused) --preserve-sha256 $pin } 'checksum mismatch'
    $damaged | save --raw -f $f.rollout
    "{\"valid\":true}\n" | save --raw ($base | path join valid)
    rejects { capture-prefix ($base | path join valid) ($base | path join refused) --preserve-sha256 (digest ($base | path join valid)) } 'names a valid file'
    0x[000a] | save --raw ($base | path join bad-first)
    rejects { capture-prefix ($base | path join bad-first) ($base | path join refused) --preserve-sha256 (digest ($base | path join bad-first)) } 'line 1'
    ($damaged ++ 0x[7b]) | save --raw ($base | path join partial)
    rejects { capture-prefix ($base | path join partial) ($base | path join refused) --preserve-sha256 (digest ($base | path join partial)) } 'incomplete tail'
    print 'PASS exact acknowledgements preserve damaged bytes and reject changes, tails, valid files, and bad metadata'

    let archive = ($base | path join live-chats.tar.gz)
    export-live $f.source $archive $f.schema.codex_version $f.schema --preserve-malformed $acknowledgement --chats-only | ignore
    let m = (unpack $archive ($base | path join verified))
    assert equal $m.scope chats
    assert equal $m.roots []
    assert equal $m.git {}
    assert equal $m.capture.preserved_malformed_rollouts $acknowledgement
    assert equal (digest ($base | path join verified codex $key)) $pin
    rejects { export-live $f.source ($base | path join unused.tar.gz) $f.schema.codex_version $f.schema --attempts 1 --chats-only --preserve-malformed {'sessions/absent.jsonl': $pin} } 'does not exist'
    rejects { export-live $f.source ($base | path join invalid.tar.gz) $f.schema.codex_version $f.schema --attempts 1 --chats-only --preserve-malformed {'../outside.jsonl': $pin} } 'Invalid malformed-history acknowledgement'
    print 'PASS chat-only live archive validates preserved history without workspace capture'

    let password = ($base | path join password)
    random uuid | save --raw $password
    chmod-mode $password 384
    let c = {repository: ($base | path join repository) state_dir: ($base | path join state) password_file: $password sources: [{kind: archive name: preserved path: $archive}]}
    restic $c [init] | ignore
    let backup = (run-backup $c)
    assert $backup.successful
    assert equal $backup.sources.preserved.backup.preserved_malformed_rollouts $acknowledgement
    let recovered = ($base | path join recovered.tar.gz)
    restore-archive $c $backup.sources.preserved.backup.snapshot_id $recovered | ignore
    rejects { import-data $f.target $recovered [] $f.schema.codex_version $f.schema } 'JSON|json|parse'
    import-data $f.target $recovered [] $f.schema.codex_version $f.schema --preserve-malformed $acknowledgement | ignore
    assert equal (digest ($f.target | path join .codex $key)) $pin
    assert (not (exists ($f.target | path join project)))
    print 'PASS encrypted backup and explicit restore retain damaged bytes without any repository files'

    rejects { require-space 100 100 } 'Insufficient staging space'
    let estimate = (require-space 10000000000 100)
    assert ($estimate.reserve_bytes >= 2147483648)
    assert ((free-bytes $base) > 0)
    print 'PASS staging preflight leaves a reserve for active guest processes'
  }
}
