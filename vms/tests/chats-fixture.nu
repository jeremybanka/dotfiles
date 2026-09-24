use ../chats/core.nu *
use ../chats/export.nu *
use ../chats/archive.nu *
use ../chats/import.nu *

export const schema_path = path self | path dirname | path join .. chats-schema.json
export def fixture [base: string] {
  let source = ($base | path join source)
  let target = ($base | path join destination-with-longer-name)
  let schema = (open $schema_path)
  for home in [$source $target] {
    mkdir ($home | path join .codex)
    'DO-NOT-EXPORT-CREDENTIAL' | save ($home | path join .codex auth.json)
    for db in ($schema.databases | transpose name template) { initialize-db ($home | path join .codex $db.name) $db.template }
  }
  let project = ($source | path join project)
  mkdir $project ($source | path join .codex sessions)
  "uncommitted fixture\n" | save --raw ($project | path join draft.txt)
  invoke [ln -s draft.txt ($project | path join link)] | ignore
  let tid = '00000000-0000-4000-8000-000000000001'
  let rollout = ($source | path join .codex sessions fixture.jsonl)
  let lines = [{type: session_meta payload: {id: $tid cwd: $project}} {type: turn_context payload: {cwd: $project text: 'unicode café'}}]
  ($lines | each {|v| $v | to json --raw } | str join "\n") + "\n" | save --raw $rollout
  sql-script ($source | path join .codex state_5.sqlite) (insert-sql threads {id: $tid rollout_path: $rollout created_at: 1 updated_at: 1 source: vscode model_provider: openai cwd: $project title: Fixture sandbox_policy: '{}' approval_mode: never history_mode: paginated name: 'Named fixture'})
  sql-script ($source | path join .codex thread_history_1.sqlite) (insert-sql thread_history_projection_state {thread_id: $tid next_rollout_byte_offset: (open --raw $rollout | into binary | bytes length) next_rollout_ordinal: 2})
  let artifact = ($base | path join archive.tar.gz)
  export-data $source $artifact $schema.codex_version | ignore
  {base: $base source: $source target: $target schema: $schema project: $project tid: $tid rollout: $rollout artifact: $artifact}
}
export def inject [f: record --dry-run --allow-missing-workspaces --before-install: closure] {
  import-data $f.target $f.artifact [] $f.schema.codex_version $f.schema --dry-run=$dry_run --allow-missing-workspaces=$allow_missing_workspaces --before-install=$before_install
}
export def reexport [f: record] {
  rm $f.artifact
  export-data $f.source $f.artifact $f.schema.codex_version | ignore
}
# Small, deterministic ustar writer for adversarial fixture archives.
def oct [n: int width: int] { (($n | format number --no-prefix | get octal | fill --alignment right --character '0' --width ($width - 1)) + (char nul)) }
def fixed [s: string width: int] {
  let b = ($s | encode utf-8)
  $b ++ (0..<(($width) - ($b | bytes length)) | each { 0x[00] } | bytes collect)
}
export def tar-member [name: string type: string data: binary target: string = ''] {
  let size = ($data | bytes length)
  let fields = [
    (fixed $name 100) (oct 420 8 | encode utf-8) (oct 0 8 | encode utf-8) (oct 0 8 | encode utf-8)
    (oct $size 12 | encode utf-8) (oct 0 12 | encode utf-8) ('        ' | encode utf-8)
    ($type | encode utf-8) (fixed $target 100) (fixed ustar 6) ('00' | encode utf-8)
    (fixed '' 32) (fixed '' 32) (oct 0 8 | encode utf-8) (oct 0 8 | encode utf-8) (fixed '' 155) (fixed '' 12)
  ]
  let header = ($fields | bytes collect)
  let checksum = ($header | chunks 1 | each {|b| $b | into int } | math sum)
  let checked = (($header | bytes at 0..<148) ++ (oct $checksum 7 | encode utf-8) ++ (' ' | encode utf-8) ++ ($header | bytes at 156..))
  let padding = ((512 - ($size mod 512)) mod 512)
  $checked ++ $data ++ (fixed '' $padding)
}
export def rewrite-archive [f: record edit: closure] {
  temporary {|tmp|
    let stage = ($tmp | path join stage)
    let m = (unpack $f.artifact $stage)
    let initial = (['codex' 'workspaces'] | each {|p| {name: $p type: '5' data: 0x[] target: ''} })
    let entries = ($initial | append ($m.files | transpose name record | each {|e|
      {name: $e.name type: (match $e.record.type {file => '0' directory => '5' symlink => '2'}) data: (if $e.record.type == file { open --raw ($stage | path join $e.name) | into binary } else { 0x[] }) target: ($e.record.target? | default '')}
    }) | append {name: manifest.json type: '0' data: ($m | to json --raw | encode utf-8) target: ''})
    let changed = (do $edit $entries)
    let raw = ($changed | each {|e| tar-member $e.name $e.type $e.data $e.target } | bytes collect)
    let bad = ($f.base | path join bad.tar.gz)
    $raw ++ (fixed '' 1024) | ^gzip -c | save --raw -f $bad
    $bad
  }
}
export def desktop-fixture [base: string] {
  let catalog = ($base | path join catalog.sqlite)
  let state = {unrelated: {keep: true} 'remote-projects': [{id: after hostId: new remotePath: /home/jem/repo label: repo} {id: before hostId: old remotePath: /home/jem/repo label: repo}] 'thread-project-assignments': {migrated: {projectKind: remote projectId: before hostId: old} other: {projectKind: remote projectId: unrelated hostId: new}}}
  let plan = {state_file: ($base | path join state.json) catalog_file: $catalog backup_dir: ($base | path join backup) app_executable: /nonexistent-test-app source_host: old target_host: new source_project: before target_project: after cwd: /home/jem/repo thread_ids: [migrated]}
  atomic-json $plan.state_file $state
  sql-script $catalog "CREATE TABLE local_thread_catalog (host_id TEXT,thread_id TEXT,cwd TEXT,PRIMARY KEY(host_id,thread_id)); INSERT INTO local_thread_catalog VALUES ('old','migrated','/home/jem/repo'),('new','migrated','/home/jem/repo'),('old','other','/home/jem/other');"
  let manifest = {export_id: fixture threads: [{id: migrated cwd: /home/jem/repo source: vscode archived: 0} {id: guardian cwd: /home/jem/repo source: '{"subagent":{"other":"guardian"}}' archived: 0} {id: archived cwd: /home/jem/repo source: vscode archived: 1}]}
  {state: $state plan: $plan catalog: $catalog manifest: $manifest}
}
