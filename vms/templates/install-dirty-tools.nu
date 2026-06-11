#!/usr/bin/env nu

use ./sandbox-policy-lib.nu *

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
  if ($helper_root | path exists) {
    rm -rf $helper_root
  }
  mkdir ($helper_root | path join "bin")
  mkdir ($helper_root | path join "usr" "bin")
  mkdir ($helper_root | path join "etc" "ssl" "certs")

  let active_policy = (load-sandbox-policy $sandbox_policy)
  let default_policy = (load-sandbox-policy $default_policy_path)

  render-sandbox-definition $default_policy | save --force $default_definition
  render-sandbox-definition $active_policy | save --force $sandbox_definition

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
  rm -f ($proxy_dir | path join "mise")
  rm -f ($proxy_dir | path join "scrubs-dirty-exec")

  ^ln -snf $dirty_exec ($proxy_dir | path join "scrubs-dirty-exec")
  cp $mise_wrapper ($proxy_dir | path join "mise")
  ^chmod 755 ($proxy_dir | path join "mise")

  link-shim-proxies $proxy_dir $mise_shims_dir $dirty_exec
}
