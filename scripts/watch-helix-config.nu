#!/usr/bin/env nu

const helix_config_dir = (path self .. | path join "home" ".config" "helix")

def main [] {
  if not ($helix_config_dir | path exists) {
    error make { msg: $"Missing Helix config directory: ($helix_config_dir)" }
  }

  print $"Watching Helix config files: ($helix_config_dir)"
  print "Save a config or theme file to reload running hx sessions."

  watch $helix_config_dir --glob '**/*.toml' --debounce 100ms --quiet { |_operation, _path, _new_path|
    reload-helix
  }
}

def reload-helix [] {
  let pids = (get-helix-pids)

  if ($pids | is-empty) {
    print "No running hx sessions found."
    return
  }

  for pid in $pids {
    ^kill -s USR1 ($pid | into string)
  }

  let session_count = ($pids | length)
  let suffix = if $session_count == 1 { "" } else { "s" }
  print $"Reloaded ($session_count) hx session($suffix)."
}

def get-helix-pids [] {
  ps
  | where name in ["hx" "helix-term"]
  | get pid
  | uniq
}
