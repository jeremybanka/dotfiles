use ../chats/core.nu *
use ../chats/export.nu *
use ../chats/import.nu [import-data]
use ../chats/schema.nu *

def main [] { help main }

# Synthetic persisted records only. Run inside an isolated home in a disposable
# guest; the host harness initializes its stores with the native app-server.
def 'main seed' [store_home: string version: string cwd: string] {
  let timestamp = '2026-09-30T23:00:00Z'
  let created = 1790809200
  let parent = '00000000-0000-4000-8000-000000015901'
  let cases = [
    {id: $parent mode: paginated turns: 103 archived: false parent: null}
    {id: '00000000-0000-4000-8000-000000015902' mode: paginated turns: 1 archived: false parent: $parent}
    {id: '00000000-0000-4000-8000-000000015903' mode: legacy turns: 1 archived: true parent: null}
  ]
  for entry in $cases {
    let folder = if $entry.archived { 'archived_sessions' } else { 'sessions' }
    let path = ($store_home | path join .codex $folder $'rollout-2026-09-30T23-00-00-($entry.id).jsonl')
    let meta = {id: $entry.id session_id: $entry.id timestamp: $timestamp cwd: $cwd originator: scrubs_chat_validation cli_version: ($version | str replace 'codex-cli ' '') source: vscode model_provider: openai history_mode: $entry.mode forked_from_id: $entry.parent base_instructions: {text: 'Synthetic backup compatibility validation.'}}
    let turns = (0..<$entry.turns | each {|n|
      let turn = $'fixture-($entry.id)-($n)'
      let question = $'Synthetic n64-2048 scoring question ($n): café.'
      let answer = $'Synthetic scoring answer ($n).'
      let items = if $entry.mode == paginated {
        [
          {type: item_completed thread_id: $entry.id turn_id: $turn started_at_ms: 100 completed_at_ms: 200 item: {type: UserMessage id: ($turn + '-user') content: [{type: text text: $question text_elements: []}]}}
          {type: item_completed thread_id: $entry.id turn_id: $turn started_at_ms: 200 completed_at_ms: 300 item: {type: AgentMessage id: ($turn + '-agent') content: [{type: Text text: $answer}] phase: final_answer}}
        ]
      } else {
        [{type: user_message message: $question images: [] local_images: [] text_elements: []} {type: agent_message message: $answer phase: final_answer}]
      }
      [{type: task_started turn_id: $turn model_context_window: 10000 collaboration_mode_kind: default}]
        | append $items
        | append {type: task_complete turn_id: $turn last_agent_message: $answer}
        | each {|payload| {type: event_msg payload: $payload} }
    } | flatten)
    let records = ([{type: session_meta payload: $meta}] | append $turns | enumerate | each {|e|
      $e.item | insert timestamp $timestamp | insert ordinal $e.index
    })
    mkdir ($path | path dirname)
    ($records | each { to json --raw } | str join "\n") + "\n" | save --raw $path
    let name = $'Synthetic ($entry.mode) ($entry.id)'
    sql-script ($store_home | path join .codex state_5.sqlite) (insert-sql threads {id: $entry.id rollout_path: $path created_at: $created updated_at: $created source: vscode model_provider: openai cwd: $cwd title: $name name: $name archived: (if $entry.archived { 1 } else { 0 }) archived_at: (if $entry.archived { $created } else { null }) sandbox_policy: '{"type":"read-only"}' approval_mode: never history_mode: $entry.mode cli_version: ($version | str replace 'codex-cli ' '') creator_user_id: fixture-user creator_account_id: fixture-account})
  }
  $cases | to json
}

def 'main export' [store_home: string version: string output: string] {
  export-live $store_home $output $version (schema-for $version) --chats-only | to json
}

def 'main import' [store_home: string version: string input: string] {
  import-data $store_home $input [] $version (schema-for $version) | to json
}
