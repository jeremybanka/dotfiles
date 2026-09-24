#!/usr/bin/env nu
use std/assert
use ../chats/core.nu *
use ../chats/archive.nu *
use ../chats/export.nu *
use ../chats/import.nu *
use ../chats/history.nu *
use ../chats/desktop.nu *
use chats-fixture.nu *
use codex-rpc.nu *
use chats-native.nu *
const desktop_cli = path self | path dirname | path join .. chats-desktop.nu

def expect-error [body: closure pattern: string] {
  let result = try { do $body | ignore; {failed: false text: ''} } catch {|e| {failed: true text: ($e.msg + " " + ($e.rendered? | default ""))} }
  assert $result.failed $"Expected failure matching ($pattern)"
  assert ($result.text =~ $pattern) $"Wrong error: ($result.text)"
}
def test [name: string body: closure --desktop] {
  temporary {|root|
    let base = ($root | path expand)
    let f = if $desktop { desktop-fixture $base } else { fixture $base }
    do $body $f
  }
  print $"PASS ($name)"
}
def main [] {
  let tests = [
    ['native verification distinguishes retained edits from current history' {|f|
      let root = ($f.source + '/.codex')
      let current = ($f.rollout | path dirname | path join replacement.jsonl)
      for entry in [{path: $f.rollout turn: old} {path: $current turn: new}] {
        [{type: session_meta payload: {id: $f.tid}} {type: event_msg payload: {type: task_started turn_id: $entry.turn}}] | each { to json --raw } | str join "\n" | save -f $entry.path
      }
      let files = ([ $f.rollout $current ] | each {|p| {key: ('codex/' + ($p | path relative-to $root)) value: {sha256: (digest $p)}} } | transpose --header-row --ignore-titles --as-record)
      let manifest = {source_home: $f.source files: $files}
      let ancestry = [{id: $f.tid path: $f.rollout} {id: $f.tid path: $current}]
      let expected = {id: $f.tid rollout_path: $current}
      let history = {
        thread_turns: {rows: [{thread_id: $f.tid turn_id: old} {thread_id: replacement-session turn_id: new}]}
        thread_items: {rows: [{thread_id: replacement-session turn_id: new item_id: new-item}]}
      }
      let turns = [{id: new items: [{id: new-item}]}]
      assert equal (check-retained-history $expected $turns $history $manifest $ancestry $root) {turns: 1 items: 1 retained_superseded_turns: [old]}
      expect-error { check-retained-history $expected [{id: old items: []}] $history $manifest $ancestry $root } 'canonical rollout'
      expect-error { check-retained-history $expected [{id: new items: []}] $history $manifest $ancestry $root } 'missing item'
      let missing = ($history | update thread_turns.rows {|v| $v.thread_turns.rows | append {thread_id: $f.tid turn_id: missing} })
      expect-error { check-retained-history $expected $turns $missing $manifest $ancestry $root } 'absent from retained'
      'tampered' | save --append $f.rollout
      expect-error { check-retained-history $expected $turns $history $manifest $ancestry $root } 'checksum mismatch'
    }]
    ['database batching deduplicates identical rows and rejects divergent keys' {|f|
      let source = ($f.source + '/.codex/state_5.sqlite')
      let target = ($f.target + '/.codex/state_5.sqlite')
      let row = (sql $source 'SELECT * FROM threads' | first)
      let ddl = (sql $source "SELECT sql FROM sqlite_master WHERE name='threads'").0.sql
      let contents = {threads: {sql: $ddl rows: [$row $row]}}
      let candidate = ($f.base + '/identical-candidate.sqlite')
      assert equal (candidate-db $target $candidate state_5.sqlite $contents $f.schema [] {}) 1
      assert equal (sql $candidate 'SELECT count(*) AS n FROM threads').0.n 1
      let divergent = {threads: {sql: $ddl rows: [$row ($row | update title Divergent)]}}
      expect-error { candidate-db $target ($f.base + '/divergent-candidate.sqlite') state_5.sqlite $divergent $f.schema [] {} } 'Chat metadata conflict'
      assert equal (sql $target 'SELECT count(*) AS n FROM threads').0.n 0
    }]
    ['native validation requires indexed turns and items' {|f|
      let history = {thread_turns: {rows: [{thread_id: t turn_id: turn}]} thread_items: {rows: [{thread_id: t turn_id: turn item_id: item}]}}
      assert equal (check-indexed-history empty [] $history) {turns: 0 items: 0}
      expect-error { check-indexed-history t [] $history } 'missing turn'
      expect-error { check-indexed-history t [{id: turn items: []}] $history } 'missing item'
      assert equal (check-indexed-history t [{id: turn items: [{id: item}]}] $history) {turns: 1 items: 1}
    }]
    ['malformed history requires an exact checksum and stays unchanged' {|f|
      0x[0000000a] | save --raw --append $f.rollout
      reexport $f
      let key = ($f.rollout | path relative-to ($f.source + '/.codex'))
      let checksum = (digest $f.rollout)
      let acknowledgement = ({} | insert $key $checksum)
      expect-error { import-data $f.source $f.artifact [] $f.schema.codex_version $f.schema } 'JSON|json'
      expect-error { import-data $f.source $f.artifact [] $f.schema.codex_version $f.schema --preserve-malformed ({} | insert $key wrong) } 'checksum mismatch'
      let result = (import-data $f.source $f.artifact [] $f.schema.codex_version $f.schema --preserve-malformed $acknowledgement)
      assert equal $result.changes 0
      assert equal $result.preserved_malformed_rollouts $acknowledgement
      assert equal (digest $f.rollout) $checksum
      expect-error { import-data $f.target $f.artifact [$"($f.project)=($f.target)/project"] $f.schema.codex_version $f.schema --preserve-malformed $acknowledgement } 'byte-for-byte unchanged'
      let tid = (open --raw $f.rollout | lines | first | from json).payload.id
      let offsets = (rewrite-rollouts ($f.source + '/.codex') {source_home: $f.source threads: [{id: $tid rollout_path: $f.rollout}]} [] --preserve-malformed $acknowledgement)
      expect-error { remap-row {thread_id: $tid rollout_byte_offset: 1} thread_turns [] $offsets } 'Unknown history byte boundary'
    }]
    ['malformed acknowledgement cannot skip metadata or name absent files' {|f|
      let key = ($f.rollout | path relative-to ($f.source + '/.codex'))
      let manifest = {source_home: $f.source threads: [{id: task rollout_path: $f.rollout}]}
      expect-error { rewrite-rollouts ($f.source + '/.codex') $manifest [] --preserve-malformed {'sessions/absent.jsonl': wrong} } 'match existing malformed files exactly'
      expect-error { rewrite-rollouts ($f.source + '/.codex') $manifest [] --preserve-malformed ({} | insert $key (digest $f.rollout)) } 'match existing malformed files exactly'
      0x[000a] | save --raw -f $f.rollout
      expect-error { rewrite-rollouts ($f.source + '/.codex') $manifest [] --preserve-malformed ({} | insert $key (digest $f.rollout)) } 'JSON|json'
    }]
    ['rotated rollouts retain earlier byte offsets without rewriting' {|f|
      let replacement = ($f.source + '/.codex/sessions/rotated.jsonl')
      let original = (open --raw $f.rollout | lines | each { from json })
      let rotated = ($original | update 0.payload ($original.0.payload | insert rotation_marker 'longer metadata in the new active rollout'))
      ($rotated | each { to json --raw } | str join "\n") + "\n" | save --raw $replacement
      sql-script ($f.source + '/.codex/state_5.sqlite') $"UPDATE threads SET rollout_path=(sql-value $replacement)"
      let fork = '00000000-0000-4000-8000-000000000002'
      sql-script ($f.source + '/.codex/state_5.sqlite') (insert-sql threads {id: $fork rollout_path: $replacement created_at: 2 updated_at: 2 source: vscode model_provider: openai cwd: $f.project title: Fork sandbox_policy: '{}' approval_mode: never history_mode: paginated})
      sql-script ($f.source + '/.codex/thread_history_1.sqlite') (insert-sql thread_history_projection_state {thread_id: $fork next_rollout_byte_offset: (open --raw $replacement | into binary | bytes length) next_rollout_ordinal: 2})
      # Keep the old projection boundary, which belongs to the retained stream.
      reexport $f
      let result = (import-data $f.source $f.artifact [] $f.schema.codex_version $f.schema)
      assert equal $result.changes 0
      assert equal $result.new_rows 0
      expect-error { inject $f } 'Shared history requires unchanged'
    }]
    ['identity mappings preserve exact histories without rewrites' {|f|
      let before = (digest $f.rollout)
      let result = (import-data $f.source $f.artifact [] $f.schema.codex_version $f.schema)
      assert equal $result.changes 0
      assert equal $result.new_rows 0
      assert equal (digest $f.rollout) $before
    }]
    ['archive batching retains entries and rejects nonadjacent duplicates' {|f|
      let entries = (0..<1025 | each {|i| tar-member $"entry/($i)" '5' 0x[] } | bytes collect)
      let ending = (0..<1024 | each { 0x[00] } | bytes collect)
      let valid = ($f.base | path join batched.tar.gz)
      ($entries ++ $ending) | ^gzip -c | save --raw $valid
      assert equal (tar-index $valid | length) 1025
      let duplicate = ($f.base | path join duplicate-across-batches.tar.gz)
      ($entries ++ (tar-member entry/0 '5' 0x[]) ++ $ending) | ^gzip -c | save --raw $duplicate
      expect-error { tar-index $duplicate } 'duplicate archive member'
    }]
    ['native tar rejects a damaged header checksum' {|f|
      let header = (tar-member codex '5' 0x[])
      let archive = ($f.base | path join damaged-header.tar.gz)
      (0x[58] ++ ($header | bytes at 1..)) | ^gzip -c | save --raw $archive
      expect-error { tar-index $archive } 'Command failed'
    }]
    ['0.154 task fields survive export and import' {|f|
      sql-script ($f.source + '/.codex/state_5.sqlite') "UPDATE threads SET originator='desktop', daybreak_enabled=0"
      reexport $f
      inject $f | ignore
      assert equal (sql ($f.target + '/.codex/state_5.sqlite') 'SELECT originator,daybreak_enabled FROM threads') [{originator: desktop daybreak_enabled: 0}]
    }]
    ['native client reports child exit' {|f|
      expect-error { rpc [sh -c 'exit 1'] [] --timeout 1sec } 'exited before completion'
    }]
    ['native client times out without hanging' {|f|
      expect-error { rpc [sh -c 'sleep 10'] [] --timeout 100ms } 'timed out'
    }]
    ['structured nulls and exact path boundaries' {|f|
      let original = {items: [null '/old/x' null '/older/x'] nested: {keep: null}}
      assert equal (transform $original [{old: /old new: /new}]) {items: [null '/new/x' null '/older/x'] nested: {keep: null}}
    }]
    ['literal filenames and executable modes' {|f|
      let p = ($f.project + '/a[1] café.txt')
      'literal' | save $p
      chmod-mode $p 493
      reexport $f
      inject $f | ignore
      let target = ($f.target + '/project/a[1] café.txt')
      assert equal (open --raw ($target | path expand)) literal
      assert equal (mode $target) 493
      assert equal (inject $f).changes 0
    }]
    ['SQLite backup preserves rowids and quoted paths' {|f|
      let source = ($f.base + '/backup-source.db')
      let dest = ($f.base + "/quote ' café\nbackup.db")
      sql-script $source "CREATE TABLE x (v TEXT); INSERT INTO x (rowid,v) VALUES (42,'kept');"
      db-backup $source $dest
      assert equal (sql $dest 'SELECT rowid,v FROM x') [{rowid: 42 v: kept}]
    }]
    ['dead owner lock reclaimed' {|f|
      let lock = ($f.base + '/dead-lock')
      mkdir $lock
      atomic-json ($lock + '/owner.json') {pid: 2147483647 started: dead}
      assert equal (with-lock $lock { 'acquired' }) acquired
      assert (not (exists $lock))
    }]
    ['active goal paused without changing accounting' {|f|
      sql-script ($f.source + '/.codex/goals_1.sqlite') (insert-sql thread_goals {thread_id: $f.tid goal_id: fixture objective: 'Keep the accounting' status: active token_budget: 1234 tokens_used: 17 time_used_seconds: 23 created_at_ms: 1 updated_at_ms: 2})
      reexport $f
      inject $f | ignore
      let goal = (sql ($f.target + '/.codex/goals_1.sqlite') 'SELECT status,tokens_used,time_used_seconds FROM thread_goals').0
      assert equal $goal {status: paused tokens_used: 17 time_used_seconds: 23}
    }]
    ['duplicate archive member rejected' {|f|
      let bad = (rewrite-archive $f {|entries| $entries | append ($entries | first) })
      expect-error { inspect-archive $bad } 'Unsafe or duplicate archive'
    }]
    ['staging permissions never follow external symlinks' {|f|
      let outside = ($f.base + '/outside.txt')
      'outside' | save $outside
      chmod-mode $outside 256
      invoke [ln -s $outside ($f.project + '/external-link')] | ignore
      reexport $f
      inspect-archive $f.artifact | ignore
      assert equal (mode $outside) 256
      chmod-mode $outside 384
    }]
    ['wrapped process names' {|f|
      for n in [codex /nix/store/example/bin/.codex-wrapped '.codex-wrapped (deleted)' codex-code-mode-host] { assert (codex-executable $n) }
      for n in [nu codex-clean.nu chats.nu] { assert (not (codex-executable $n)) }
    }]
    ['export excludes credentials and keeps source' {|f|
      let m = (inspect-archive $f.artifact)
      assert equal $m.threads.0.title 'Named fixture'
      assert equal $m.missing []
      assert (exists $f.rollout)
      assert (tar-index $f.artifact | all {|r| not ($r.name | str contains auth.json) })
    }]
    ['attachment index merge and conflict checks' {|f|
      let src = ($f.source + '/.codex/attachments/source.txt')
      let dst = ($f.target + '/.codex/attachments/old.txt')
      let incoming = {attachmentPaths: [$src] pendingRemovalPaths: [] textExcerptsByPath: {($src): ('literal ' + $src)}}
      let existing = {attachmentPaths: [$dst] pendingRemovalPaths: [] textExcerptsByPath: {($dst): keep}}
      let maps = (mappings $f.source $f.target [])
      let merged = (merge-pasted-index $existing $incoming $maps)
      assert equal $merged.attachmentPaths [$dst (mapped $src $maps)]
      assert equal (merge-pasted-index $merged $incoming $maps) $merged
      expect-error { merge-pasted-index $merged ($incoming | update textExcerptsByPath {($src): different}) $maps } 'excerpt conflict'
      expect-error { merge-pasted-index $existing ($incoming | update pendingRemovalPaths [$src]) $maps } 'pending'
    }]
    ['attachment import preserves both guests' {|f|
      for pair in [{home: $f.source name: source} {home: $f.target name: destination}] {
        let p = ($pair.home + '/.codex/attachments/' + $pair.name + '/pasted-text.txt')
        mkdir ($p | path dirname)
        $pair.name | save $p
        atomic-json ($pair.home + '/.codex/attachments/pasted-text-attachments.json') {attachmentPaths: [$p] pendingRemovalPaths: [] textExcerptsByPath: {($p): $pair.name}}
      }
      reexport $f
      inject $f | ignore
      let index = (open ($f.target + '/.codex/attachments/pasted-text-attachments.json'))
      assert equal ($index.attachmentPaths | length) 2
      assert ($index.attachmentPaths | all {|p| exists $p })
      assert equal (inject $f).changes 0
    }]
    ['shared history byte preservation and relocation refusal' {|f|
      let base = ($f.source + '/.codex/sessions/base.jsonl')
      let bytes = (open --raw $f.rollout | into binary)
      $bytes | save --raw $base
      let meta = (open --raw $f.rollout | lines | first | from json | upsert payload.history_base {thread_id: $f.tid end_ordinal_exclusive: 2 end_byte_offset: ($bytes | bytes length)})
      ($meta | to json --raw) + "\n" | save --raw -f $f.rollout
      let manifest = {source_home: $f.source threads: [{id: $f.tid rollout_path: $f.rollout}]}
      let result = (rewrite-rollouts ($f.source + '/.codex') $manifest [])
      assert equal ($result | get $f.tid | get (($bytes | bytes length) | into string)) ($bytes | bytes length)
      assert equal (open --raw $base | into binary) $bytes
      expect-error { rewrite-rollouts ($f.source + '/.codex') $manifest (mappings $f.source $f.target []) } 'Shared history requires unchanged'
    }]
    ['dry run changes nothing' {|f|
      let before = (digest ($f.target + '/.codex/state_5.sqlite'))
      assert (inject $f --dry-run).dry_run
      assert (not (exists ($f.target + '/project')))
      assert equal (digest ($f.target + '/.codex/state_5.sqlite')) $before
    }]
    ['registered temporary Git worktree' {|f|
      for args in [[init] [add .] [-c user.name=Fixture -c user.email=fixture@example.invalid commit -m fixture]] { invoke ([git -C $f.project] | append $args) | ignore }
      let linked = ($f.base + '/temporary-worktree')
      invoke [git -C $f.project worktree add -b linked $linked] | ignore
      rm ($linked + '/draft.txt')
      reexport $f
      assert equal (inspect-archive $f.artifact).missing []
      let moved = ($f.target + '/linked')
      import-data $f.target $f.artifact [($linked + '=' + $moved)] $f.schema.codex_version $f.schema | ignore
      assert (invoke [git -C $moved status --porcelain] | str contains ' D draft.txt')
    }]
    ['round trip offsets and idempotence' {|f|
      inject $f | ignore
      let restored = ($f.target + '/.codex/sessions/fixture.jsonl')
      assert equal (open --raw ($f.target + '/project/draft.txt')) "uncommitted fixture\n"
      assert equal (open --raw $restored | lines | first | from json).payload.cwd ($f.target + '/project')
      assert equal (sql ($f.target + '/.codex/thread_history_1.sqlite') 'SELECT next_rollout_byte_offset FROM thread_history_projection_state').0.next_rollout_byte_offset (open --raw $restored | into binary | bytes length)
      assert equal (inject $f).changes 0
      assert equal (open --raw ($f.target + '/.codex/auth.json')) DO-NOT-EXPORT-CREDENTIAL
    }]
    ['populated destination preserved' {|f|
      sql-script ($f.target + '/.codex/state_5.sqlite') (insert-sql threads {id: native rollout_path: /native.jsonl created_at: 1 updated_at: 1 source: exec model_provider: openai cwd: /native title: Native sandbox_policy: '{}' approval_mode: never})
      inject $f | ignore
      assert equal (sql ($f.target + '/.codex/state_5.sqlite') "SELECT title FROM threads WHERE id='native'").0.title Native
      assert equal (sql ($f.target + '/.codex/state_5.sqlite') 'SELECT count(*) AS n FROM threads').0.n 2
    }]
    ['workspace conflict is nondestructive' {|f|
      mkdir ($f.target + '/project')
      'valuable destination work' | save ($f.target + '/project/draft.txt')
      expect-error { inject $f } 'Workspace conflict'
      assert equal (open --raw ($f.target + '/project/draft.txt')) 'valuable destination work'
      assert (not (exists ($f.target + '/.codex/sessions')))
    }]
    ['divergent chat refused' {|f|
      inject $f | ignore
      "{\"new\":\"conversation turn\"}\n" | save --raw --append ($f.target + '/.codex/sessions/fixture.jsonl')
      expect-error { inject $f } 'Chat file conflict'
    }]
    ['version mismatch refused' {|f| expect-error { import-data $f.target $f.artifact [] 'codex-cli 999.0' $f.schema } 'adapter requires' }]
    ['concurrent transfer refused' {|f|
      let lock = ($f.target + '/.codex/lock')
      with-lock $lock { expect-error { with-lock $lock { fail 'lock entered twice' } } 'Another migration' }
    }]
    ['broad workspace omitted but chat retained' {|f|
      sql ($f.source + '/.codex/state_5.sqlite') $"UPDATE threads SET cwd=(sql-value $f.source)" | ignore
      reexport $f
      let m = (inspect-archive $f.artifact)
      assert equal ($m.threads | length) 1
      assert equal $m.roots []
      expect-error { inject $f } 'Archive is incomplete'
      assert ((inject $f --allow-missing-workspaces).missing_workspaces != [])
    }]
    ['symlink workspace root rejected' {|f|
      let bad = (rewrite-archive $f {|entries| $entries | each {|e|
        if $e.name == manifest.json {
          let m = ($e.data | decode utf-8 | from json)
          let files = ($m.files | update 'workspaces/0' (($m.files | get 'workspaces/0') | update type symlink))
          $e | update data ($m | update files $files | to json --raw | encode utf-8)
        } else { $e }
      } })
      expect-error { inspect-archive $bad } 'root must be a directory'
    }]
    ['metadata conflict prevents files' {|f|
      sql-script ($f.target + '/.codex/state_5.sqlite') (insert-sql threads {id: $f.tid rollout_path: /different.jsonl created_at: 1 updated_at: 1 source: exec model_provider: openai cwd: /different title: Conflict sandbox_policy: '{}' approval_mode: never})
      expect-error { inject $f } 'Chat metadata conflict'
      assert (not (exists ($f.target + '/project')))
    }]
    ['empty Codex databases initialized' {|f|
      rm ...(glob ($f.target + '/.codex/*.sqlite'))
      assert ((inject $f).new_rows > 0)
      assert equal (sql ($f.target + '/.codex/state_5.sqlite') 'SELECT name FROM threads').0.name 'Named fixture'
    }]
    ['interrupted import recovery' {|f|
      let journal = ($f.target + '/.codex/scrubs-chat-imports/pending-fixture')
      mkdir $journal ($f.target + '/partial')
      'overwritten' | save ($f.target + '/existing')
      'original' | save ($journal + '/0.backup')
      'partial' | save ($f.target + '/partial/file')
      atomic-json ($journal + '/journal.json') {changes: [{target: ($f.target + '/existing') backup: 0.backup} {target: ($f.target + '/partial')}]}
      assert equal (recover-data $f.target).rolled_back 1
      assert equal (open --raw ($f.target + '/existing')) original
      assert (not (exists ($f.target + '/partial')))
    }]
    ['checksum corruption rejected' {|f|
      let bad = (rewrite-archive $f {|entries| $entries | each {|e| if ($e.name | str ends-with draft.txt) { $e | update data ('corrupted12345678901' | encode utf-8) } else { $e } } })
      expect-error { inspect-archive $bad } 'Checksum|Size mismatch'
    }]
    ['path traversal rejected' {|f|
      let bad = (rewrite-archive $f {|entries| $entries | append {name: ../escaped type: '0' data: 0x[61] target: ''} })
      expect-error { inspect-archive $bad } 'Unsafe or duplicate archive'
      assert (not (exists ($f.base + '/escaped')))
    }]
    ['payload through symlink rejected' {|f|
      let bad = (rewrite-archive $f {|entries| $entries | append {name: workspaces/0/link/escaped type: '0' data: 0x[61] target: ''} })
      expect-error { inspect-archive $bad } 'symlink'
    }]
    ['credential payload injection rejected' {|f|
      let bad = (rewrite-archive $f {|entries| $entries | each {|e| if $e.name == manifest.json { $e | update data ($e.data | decode utf-8 | from json | update files {|v| $v.files | insert 'codex/auth.json' {type: file size: 1 sha256: bad mode: 384} } | to json --raw | encode utf-8) } else { $e } } | append {name: codex/auth.json type: '0' data: 0x[61] target: ''} })
      expect-error { inspect-archive $bad } 'Unexpected payload'
    }]
    ['installation failure rolls back workspace' {|f|
      expect-error { inject $f --before-install { 'blocked' | save ($f.target + '/.codex/sessions') } } 'directory|Directory|Already exists'
      assert (not (exists ($f.target + '/project')))
      assert equal (glob ($f.target + '/.codex/scrubs-chat-imports/pending-*')) []
      assert equal (sql ($f.target + '/.codex/state_5.sqlite') 'SELECT count(*) AS n FROM threads').0.n 0
    }]
  ]
  for t in $tests { test $t.0 $t.1 }
  let desktop_tests = [
    ['verified catalog seeds apply and recover without touching other rows' {|f|
      sql $f.catalog "DELETE FROM local_thread_catalog WHERE host_id='new'" | ignore
      let proof = {threads: [{id: migrated cwd: /home/jem/repo}]}
      let plan = (with-catalog-seeds $f.plan $f.catalog $proof)
      assert equal (verify-plan $plan).destination_catalog_rows_to_add [migrated]
      assert (apply-plan $plan).applied
      assert (verify-plan $plan).verified
      assert (apply-plan $plan).already_applied
      rm ($plan.backup_dir + '/result.json')
      assert (recover-plan $plan).rolled_back
      assert equal (open $plan.state_file) $f.state
      assert equal (sql $f.catalog "SELECT count(*) AS n FROM local_thread_catalog WHERE host_id='new'").0.n 0
      assert equal (sql $f.catalog 'SELECT count(*) AS n FROM local_thread_catalog').0.n 2
    }]
    ['catalog seeds require matching native proof and unchanged source' {|f|
      sql $f.catalog "DELETE FROM local_thread_catalog WHERE host_id='new'" | ignore
      expect-error { with-catalog-seeds $f.plan $f.catalog {threads: []} } 'Native verification'
      expect-error { with-catalog-seeds $f.plan $f.catalog {threads: [{id: migrated cwd: /wrong}]} } 'Native verification'
      let plan = (with-catalog-seeds $f.plan $f.catalog {threads: [{id: migrated cwd: /home/jem/repo}]})
      expect-error { verify-plan ($plan | update catalog_seeds.0.verified.cwd /wrong) } 'native verification'
      sql $f.catalog "UPDATE local_thread_catalog SET cwd='/changed' WHERE host_id='old' AND thread_id='migrated'" | ignore
      expect-error { verify-plan $plan } 'Source catalog entry changed'
      assert (not (exists $plan.backup_dir))
    }]
    ['catalog seed recovery refuses subsequent destination edits' {|f|
      sql $f.catalog "DELETE FROM local_thread_catalog WHERE host_id='new'" | ignore
      let plan = (with-catalog-seeds $f.plan $f.catalog {threads: [{id: migrated cwd: /home/jem/repo}]})
      apply-plan $plan | ignore
      rm ($plan.backup_dir + '/result.json')
      sql $f.catalog "UPDATE local_thread_catalog SET cwd='/changed' WHERE host_id='new'" | ignore
      expect-error { recover-plan $plan } 'Added catalog row changed'
      assert equal (sql $f.catalog "SELECT cwd FROM local_thread_catalog WHERE host_id='new'").0.cwd /changed
    }]
    ['batch preflight and multiple source hosts' {|f|
      let first = ($f.plan | insert app_bundle /nonexistent-test-app)
      let second = ($first | update source_host old2 | update thread_ids [migrated2] | update backup_dir ($f.plan.backup_dir + '-two'))
      let one = ($f.plan.state_file + '.one.json')
      let two = ($f.plan.state_file + '.two.json')
      let batch = ($f.plan.state_file + '.batch.json')
      atomic-json $one $first
      atomic-json $two $second
      atomic-json $batch [$one $two]
      expect-error { invoke [$nu.current-exe --no-config-file $desktop_cli apply-batch $batch] } 'Destination catalog'
      assert equal (open $f.plan.state_file) $f.state
      assert (not (exists $first.backup_dir))
      sql-script $f.catalog "INSERT INTO local_thread_catalog VALUES ('old2','migrated2','/home/jem/repo'),('new','migrated2','/home/jem/repo');"
      invoke [$nu.current-exe --no-config-file $desktop_cli apply-batch $batch] | ignore
      assert (verify-plan $first).verified
      assert (verify-plan $second).verified
      invoke [$nu.current-exe --no-config-file $desktop_cli apply-batch $batch] | ignore
      assert equal (sql $f.catalog "SELECT count(*) AS n FROM local_thread_catalog WHERE host_id IN ('old','old2')").0.n 1
    }]
    ['running app refused' {|f|
      let executable = (invoke [ps -p ($nu.pid | into string) -o comm=] | str trim)
      expect-error { apply-plan ($f.plan | update app_executable $executable) } 'Close Codex'
      assert (not (exists $f.plan.backup_dir))
      assert equal (open $f.plan.state_file) $f.state
    }]
    ['scoped repair backup and idempotence' {|f|
      assert (apply-plan $f.plan).applied
      assert (apply-plan $f.plan).already_applied
      assert (verify-plan $f.plan).verified
      let expected = ($f.state | update 'thread-project-assignments' {|v| $v."thread-project-assignments" | update migrated {projectKind: remote projectId: after hostId: new} })
      assert equal (open $f.plan.state_file) $expected
      assert equal (open ($f.plan.backup_dir + '/global-state.before.json')) $f.state
      assert equal (sql $f.catalog 'SELECT count(*) AS n FROM local_thread_catalog').0.n 2
    }]
    ['missing destination refused' {|f|
      sql $f.catalog "DELETE FROM local_thread_catalog WHERE host_id='new'" | ignore
      expect-error { plan-changes $f.state $f.catalog $f.plan } 'Destination catalog'
    }]
    ['new user assignment refused' {|f|
      let state = ($f.state | update 'thread-project-assignments' {|v| $v."thread-project-assignments" | update migrated.projectId changed-by-user })
      expect-error { plan-changes $state $f.catalog $f.plan } 'unexpected project'
    }]
    ['discover IDs and skip internal records' {|f|
      let plan = (make-plan $f.state $f.manifest old new [])
      assert equal $plan.migrations.0.thread_ids [migrated]
      assert equal $plan.migrations.0.target_project after
      assert equal ($plan.skipped_sidebar_records | length) 2
      assert equal (plan-changes $f.state $f.catalog $plan).report.assignments_to_update [migrated]
    }]
    ['create missing target project and remap cwd' {|f|
      let state = ($f.state | update 'remote-projects' {|v| $v."remote-projects" | where hostId != new })
      let plan = (make-plan $state $f.manifest old new [{old: /home/jem/repo new: /home/jem/moved}])
      sql $f.catalog "UPDATE local_thread_catalog SET cwd='/home/jem/moved' WHERE host_id='new'" | ignore
      let next = (plan-changes $state $f.catalog $plan)
      assert equal ($next.report.projects_to_create | length) 1
      assert equal (plan-changes $next.state $f.catalog $plan).report.projects_to_create []
    }]
    ['missing task never silently skipped' {|f|
      let m = ($f.manifest | update threads {|v| $v.threads | append {id: not-discovered cwd: /home/jem/repo source: cli} })
      let plan = (make-plan $f.state $m old new [])
      expect-error { plan-changes $f.state $f.catalog $plan } 'not-discovered'
    }]
    ['multiple projects and worktree association' {|f|
      let state = ($f.state | update 'remote-projects' {|v| $v."remote-projects" | append {id: second hostId: old remotePath: /home/jem/two label: two} })
      let m = ($f.manifest | update threads {|v| $v.threads | append {id: worktree cwd: /home/jem/.codex/worktrees/abc/two source: cli} } | insert git {'/home/jem/.codex/worktrees/abc/two': {common_dir: /home/jem/two/.git}})
      let plan = (make-plan $state $m old new [])
      assert equal ($plan.migrations | length) 2
      assert equal $plan.migrations.1.project_root /home/jem/two
    }]
    ['unknown sidebar source refused' {|f|
      let m = ($f.manifest | update threads {|v| $v.threads | update 0.source future-kind })
      expect-error { make-plan $f.state $m old new [] } 'Unknown sidebar source'
    }]
    ['interrupted desktop repair recovery' {|f|
      apply-plan $f.plan | ignore
      rm ($f.plan.backup_dir + '/result.json')
      assert (recover-plan $f.plan).rolled_back
      assert equal (open $f.plan.state_file) $f.state
      assert equal (sql $f.catalog 'SELECT count(*) AS n FROM local_thread_catalog').0.n 3
    }]
    ['desktop recovery refuses subsequent edits' {|f|
      apply-plan $f.plan | ignore
      rm ($f.plan.backup_dir + '/result.json')
      atomic-json $f.plan.state_file ((open $f.plan.state_file) | insert new-user-setting true)
      expect-error { recover-plan $f.plan } 'changed since migration'
    }]
  ]
  for t in $desktop_tests { test $t.0 $t.1 --desktop }
  print $"PASS (($tests | length) + ($desktop_tests | length)) regression tests"
}
