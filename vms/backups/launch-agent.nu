use ../chats/core.nu *
use core.nu [prepare-state private-file]

export const agent_label = 'com.jeremybanka.codex-chat-backups'
const source_dir = path self | path dirname | path dirname
const cli = path self | path dirname | path join .. chat-backups.nu

def xml [s: string] {
  $s | str replace --all '&' '&amp;' | str replace --all '<' '&lt;' | str replace --all '>' '&gt;' | str replace --all '"' '&quot;'
}
export def agent-text [c: record script: string hour: int minute: int] {
  if $hour < 0 or $hour > 23 or $minute < 0 or $minute > 59 { fail 'Invalid daily schedule time' }
  let args = ([$nu.current-exe --no-config-file $script run $c.config_path] | each {|v| '<string>' + (xml $v) + '</string>' } | str join "\n")
  let path = (xml ($env.PATH | str join ':'))
  let stdout = (xml ($c.state_dir | path join launch.stdout.log))
  let stderr = (xml ($c.state_dir | path join launch.stderr.log))
  '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>' + $agent_label + '</string>
<key>ProgramArguments</key><array>' + $args + '</array>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>' + $path + '</string></dict>
<key>StartCalendarInterval</key><dict><key>Hour</key><integer>' + ($hour | into string) + '</integer><key>Minute</key><integer>' + ($minute | into string) + '</integer></dict>
<key>RunAtLoad</key><false/>
<key>ProcessType</key><string>Background</string>
<key>LowPriorityIO</key><true/>
<key>Umask</key><integer>63</integer>
<key>StandardOutPath</key><string>' + $stdout + '</string>
<key>StandardErrorPath</key><string>' + $stderr + '</string>
</dict></plist>'
}
export def write-agent [c: record output: string --hour: int = 3 --minute: int = 0 --script: string] {
  if $nu.os-info.name != macos { fail 'Launch agents require macOS' }
  let script_path = ($script | default $cli | path expand)
  let body = (agent-text $c $script_path $hour $minute)
  no-links $output
  if (exists $output) { fail 'Agent plist already exists; inspect it before replacing' }
  # Resolve tools now: launchd does not load the interactive shell/mise setup.
  for tool in ([restic sqlite3 tar gzip git] | append (if ($c.sources | any {|s| $s.kind == guest }) { [limactl] } else { [] })) {
    if (which $tool | is-empty) { fail $'Required host tool is unavailable: ($tool)' }
  }
  prepare-state $c
  for name in [launch.stdout.log launch.stderr.log] {
    let p = ($c.state_dir | path join $name)
    no-links $p
    if not (exists $p) { '' | save --raw $p }
    invoke [chmod '600' $p] | ignore
  }
  mkdir ($output | path dirname)
  $body | save --raw $output
  invoke [chmod '600' $output] | ignore
  invoke [plutil -lint $output] | ignore
  {plist: $output label: $agent_label hour: $hour minute: $minute loaded: false}
}
export def install-agent [c: record --hour: int = 3 --minute: int = 0 --load] {
  private-file $c.config_path
  let plist = ($env.HOME | path join Library LaunchAgents ($agent_label + '.plist'))
  no-links $plist
  if (exists $plist) { fail 'Launch agent already installed; unload and inspect it before replacing' }
  # Immutable installed copy survives checkout/branch changes and /tmp cleanup.
  let runtime = ($env.HOME | path join Library 'Application Support' CodexChatBackups ('runtime-' + (random uuid)))
  no-links $runtime
  mkdir $runtime
  invoke [chmod '700' $runtime] | ignore
  try {
    for name in [chat-backups.nu chats.nu chats-schema.json backups chats] {
      invoke [cp -R ($source_dir | path join $name) ($runtime | path join $name)] | ignore
    }
    let result = (write-agent $c $plist --hour $hour --minute $minute --script ($runtime | path join chat-backups.nu))
    if $load { invoke [launchctl bootstrap ('gui/' + (invoke [id -u])) $plist] | ignore }
    $result | update loaded $load | insert runtime $runtime
  } catch {|e|
    # Keep the runtime/plist for diagnosis if launchctl might have loaded the job.
    error make $e
  }
}
