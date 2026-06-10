export def normalize-sandbox-policy [policy: record] {
  {
    primary_shell: ($policy.primary_shell | into string)
    helper_commands: ($policy.helper_commands | each {|value| $value | into string })
    helper_copy_files: ($policy.helper_copy_files | each {|value| $value | into string })
    helper_link_files: ($policy.helper_link_files | each {|value| $value | into string })
    dir_paths: ($policy.dir_paths | each {|value| $value | into string })
    ro_bind_paths: ($policy.ro_bind_paths | each {|value| $value | into string })
    enable_proc: ($policy.enable_proc | into bool)
  }
}

export def load-sandbox-policy [path: string] {
  normalize-sandbox-policy (open $path)
}

export def shell-quote [value: string] {
  let escaped = ($value | str replace --all "'" "'\"'\"'")
  "'" + $escaped + "'"
}

export def render-shell-list [values: list<string>] {
  if ($values | is-empty) {
    "(\n)"
  } else {
    let lines = ($values | each {|value| "  " + (shell-quote $value) } | str join "\n")
    "(\n" + $lines + "\n)"
  }
}

export def render-sandbox-definition [policy: record] {
  let helper_commands = (render-shell-list $policy.helper_commands)
  let helper_copy_files = (render-shell-list $policy.helper_copy_files)
  let helper_link_files = (render-shell-list $policy.helper_link_files)
  let dir_paths = (render-shell-list $policy.dir_paths)
  let ro_bind_paths = (render-shell-list $policy.ro_bind_paths)
  let enable_proc = if $policy.enable_proc { "1" } else { "0" }

  [
    "#!/bin/bash"
    ""
    $"SCRUBS_PRIMARY_SHELL=(shell-quote $policy.primary_shell)"
    ""
    $"SCRUBS_HELPER_COMMANDS=($helper_commands)"
    ""
    $"SCRUBS_HELPER_COPY_FILES=($helper_copy_files)"
    ""
    $"SCRUBS_HELPER_LINK_FILES=($helper_link_files)"
    ""
    $"SCRUBS_DIR_PATHS=($dir_paths)"
    ""
    $"SCRUBS_RO_BIND_PATHS=($ro_bind_paths)"
    ""
    $"SCRUBS_ENABLE_PROC=($enable_proc)"
    ""
  ] | str join "\n"
}
