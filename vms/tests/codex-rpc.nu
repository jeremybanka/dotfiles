# Small native app-server client. FIFOs keep stdin open until all replies arrive.
# Only the fixed descriptor bridge uses sh; protocol and lifecycle live in Nu.
use ../chats/core.nu *

export def rpc [command: list requests: list --timeout: duration = 60sec --cleanup: closure] {
  temporary {|temp|
    let input = ($temp | path join requests.fifo)
    let output = ($temp | path join responses.fifo)
    let stopped = ($temp | path join stopped)
    invoke [mkfifo -m 600 $input $output] | ignore
    let server = (job spawn {
      ^sh -c 'exec 3<>"$1"; exec 4<>"$2"; stopped=$3; shift 3; "$@" <&3 >&4; printf "%s\n" "{\"id\":1,\"error\":{\"message\":\"Codex app-server exited before completion\"}}" >&4; while [ ! -f "$stopped" ]; do sleep 0.1; done' scrubs-rpc $input $output $stopped ...$command e> ($temp | path join server.log)
    })
    let watchdog = (job spawn {
      sleep $timeout
      if $cleanup != null { try { do $cleanup } }
      ({id: 1 error: {message: 'Codex RPC timed out'}} | to json --raw) + "\n" | save --raw --append $output
    })
    try {
      ({id: 1 method: initialize params: {clientInfo: {name: scrubs_chat_validation version: '2'} capabilities: {experimentalApi: true}}} | to json --raw) + "\n" | save --raw --append $input
      mut responses = {}
      mut initialized = false
      for line in (open --raw $output | lines) {
        let msg = ($line | from json)
        if $msg.id? == 1 {
          if $msg.error? != null { fail $"Codex initialization failed: ($msg.error | to json --raw)" }
          $initialized = true
          let batch = ([{method: initialized}] | append ($requests | enumerate | each {|r| $r.item | insert id ($r.index + 2) }))
          ($batch | each {|r| $r | to json --raw } | str join "\n") + "\n" | save --raw --append $input
          if ($requests | is-empty) { break }
        } else if $msg.id? != null {
          if not $initialized or $msg.id < 2 or $msg.id >= (($requests | length) + 2) { fail 'Unexpected RPC response ID' }
          if $msg.error? != null { fail $"Codex RPC failed: ($msg.error | to json --raw)" }
          $responses = ($responses | insert ($msg.id | into string) $msg.result)
          if ($responses | columns | length) == ($requests | length) { break }
        }
      }
      try { job kill $watchdog }
      if $cleanup != null { do $cleanup }
      '' | save --raw $stopped
      try { job kill $server }
      if not $initialized or ($responses | columns | length) != ($requests | length) { fail 'Codex RPC timed out or exited before all responses' }
      let replies = $responses
      $requests | enumerate | each {|r| $replies | get (($r.index + 2) | into string) }
    } catch {|e|
      try { job kill $watchdog }
      if $cleanup != null { try { do $cleanup } }
      try { '' | save --raw $stopped }
      try { job kill $server }
      error make $e
    }
  }
}

export def guest-rpc [instance: string requests: list --timeout: duration = 120sec] {
  let pidfile = '/tmp/scrubs-rpc-' + (random uuid) + '.pid'
  let cleanup = {
    invoke [limactl shell $instance -- sh -c 'if [ -f "$1" ]; then read -r pid < "$1"; rm -f "$1"; kill -TERM "$pid" 2>/dev/null || true; fi' scrubs-stop $pidfile] | ignore
  }
  rpc [limactl shell $instance -- sh -c 'umask 077; echo $$ > "$1"; shift; exec "$@"' scrubs-server $pidfile /run/current-system/sw/bin/codex -c mcp_servers.playwright.enabled=false -c mcp_servers.playwright.required=false app-server] $requests --timeout $timeout --cleanup $cleanup
}
