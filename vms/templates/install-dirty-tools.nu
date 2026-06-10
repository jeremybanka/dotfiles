#!/usr/bin/env nu

def sh-quote [value: string] {
  let escaped = ($value | str replace --all "'" "'\"'\"'")
  "'" + $escaped + "'"
}

def shell-array [values: list<string>] {
  if ($values | is-empty) {
    "(\n)"
  } else {
    let lines = ($values | each {|value| "  " + (sh-quote $value) } | str join "\n")
    "(\n" + $lines + "\n)"
  }
}

def normalize-policy [policy: record] {
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

def load-policy [path: string] {
  normalize-policy (open $path)
}

def render-shell-policy [policy: record] {
  let helper_commands = (shell-array $policy.helper_commands)
  let helper_copy_files = (shell-array $policy.helper_copy_files)
  let helper_link_files = (shell-array $policy.helper_link_files)
  let dir_paths = (shell-array $policy.dir_paths)
  let ro_bind_paths = (shell-array $policy.ro_bind_paths)
  let enable_proc = if $policy.enable_proc { "1" } else { "0" }

  [
    "#!/bin/bash"
    ""
    $"SCRUBS_PRIMARY_SHELL=(sh-quote $policy.primary_shell)"
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

def resolve-command-path [command_name: string] {
  let clean_path = $"/run/current-system/sw/bin/($command_name)"

  if ($clean_path | path exists) {
    return ($clean_path | path expand)
  }

  let matches = (try { which $command_name } catch { [] } | where type == "external")
  if ($matches | is-empty) {
    return ""
  }

  $matches | get 0.path | path expand
}

def copy-text-file [src: string, dst: string] {
  if not ($src | path exists) {
    return
  }

  mkdir ($dst | path dirname)
  rm -f $dst
  cp $src $dst
  ^chmod u+w $dst
}

def link-helper [src: string, dst: string] {
  if $src == "" or not ($src | path exists) {
    return
  }

  mkdir ($dst | path dirname)
  ^ln -snf ($src | path expand) $dst
}

def remove-generated-proxies [proxy_dir: string, dirty_exec: string] {
  for proxy_path in (glob ($proxy_dir | path join "*")) {
    let readlink_result = (^readlink $proxy_path | complete)
    if $readlink_result.exit_code == 0 and (($readlink_result.stdout | str trim) == $dirty_exec) {
      rm -f $proxy_path
    }
  }
}

def link-shim-proxies [proxy_dir: string, mise_shims_dir: string, dirty_exec: string] {
  if not ($mise_shims_dir | path exists) {
    return
  }

  for shim_path in (glob ($mise_shims_dir | path join "*")) {
    if not ($shim_path | path exists) {
      continue
    }

    let shim_type = ($shim_path | path type)
    if $shim_type not-in ["file", "symlink"] {
      continue
    }

    let command_name = ($shim_path | path basename)
    if $command_name == "mise" {
      continue
    }

    ^ln -snf $dirty_exec ($proxy_dir | path join $command_name)
  }
}

def main [] {
  let scrubs_dir = ($env.HOME | path join ".local" "libexec" "scrubs")
  let proxy_dir = ($env.HOME | path join ".local" "bin")
  let helper_root = ($env.HOME | path join ".local" "share" "scrubs" "helper-root")
  let dirty_exec = ($scrubs_dir | path join "dirty-exec.sh")
  let mise_wrapper = ($scrubs_dir | path join "mise-wrapper.sh")
  let sandbox_policy = ($scrubs_dir | path join "sandbox-policy.nuon")
  let sandbox_definition = ($scrubs_dir | path join "sandbox-definition.sh")
  let default_policy_path = ($scrubs_dir | path join "sandbox-default-policy.nuon")
  let default_definition = ($scrubs_dir | path join "sandbox-default-definition.sh")
  let mise_shims_dir = ($env.HOME | path join ".local" "share" "mise" "shims")

  if not ($sandbox_policy | path exists) {
    error make { msg: $"scrubs dirty tools: missing sandbox policy at ($sandbox_policy)" }
  }

  if not ($default_policy_path | path exists) {
    error make { msg: $"scrubs dirty tools: missing default sandbox policy at ($default_policy_path)" }
  }

  mkdir $proxy_dir
  mkdir ($helper_root | path join "bin")
  mkdir ($helper_root | path join "usr" "bin")
  mkdir ($helper_root | path join "etc" "ssl" "certs")

  let active_policy = (load-policy $sandbox_policy)
  let default_policy = (load-policy $default_policy_path)

  render-shell-policy $default_policy | save --force $default_definition
  render-shell-policy $active_policy | save --force $sandbox_definition

  for helper_file in $active_policy.helper_copy_files {
    copy-text-file $helper_file ($helper_root | path join ($helper_file | str replace --regex '^/' ""))
  }

  for helper_file in $active_policy.helper_link_files {
    link-helper $helper_file ($helper_root | path join ($helper_file | str replace --regex '^/' ""))
  }

  let primary_shell_path = (resolve-command-path $active_policy.primary_shell)
  if $primary_shell_path == "" {
    error make { msg: $"scrubs dirty tools: missing primary shell '($active_policy.primary_shell)'" }
  }

  link-helper $primary_shell_path ($helper_root | path join "bin" $active_policy.primary_shell)
  ^ln -snf $active_policy.primary_shell ($helper_root | path join "bin" "sh")

  for command_name in $active_policy.helper_commands {
    let resolved = (resolve-command-path $command_name)
    if $resolved != "" {
      link-helper $resolved ($helper_root | path join "usr" "bin" $command_name)
    }
  }

  remove-generated-proxies $proxy_dir $dirty_exec

  ^ln -snf $dirty_exec ($proxy_dir | path join "scrubs-dirty-exec")
  cp $mise_wrapper ($proxy_dir | path join "mise")
  ^chmod 755 ($proxy_dir | path join "mise")

  link-shim-proxies $proxy_dir $mise_shims_dir $dirty_exec
}
