#!/usr/bin/env nu

use ./lib.nu *

def ssh-base-args [guest_user: string, ssh_port: string] {
  [
    "-o" "ControlMaster=no"
    "-o" "ControlPath=none"
    "-o" "ControlPersist=no"
    "-o" "StrictHostKeyChecking=no"
    "-o" "UserKnownHostsFile=/dev/null"
    "-o" "NoHostAuthenticationForLocalhost=yes"
    "-o" "PreferredAuthentications=publickey"
    "-o" "Compression=no"
    "-o" "BatchMode=yes"
    "-o" "IdentitiesOnly=yes"
    "-o" "GSSAPIAuthentication=no"
    "-i" ($env.HOME | path join ".lima" "_config" "user")
    "-p" $ssh_port
    $"($guest_user)@127.0.0.1"
  ]
}

def scp-base-args [ssh_port: string] {
  [
    "-o" "StrictHostKeyChecking=no"
    "-o" "UserKnownHostsFile=/dev/null"
    "-o" "NoHostAuthenticationForLocalhost=yes"
    "-o" "PreferredAuthentications=publickey"
    "-o" "Compression=no"
    "-o" "BatchMode=yes"
    "-o" "IdentitiesOnly=yes"
    "-o" "GSSAPIAuthentication=no"
    "-i" ($env.HOME | path join ".lima" "_config" "user")
    "-P" $ssh_port
    "-r"
  ]
}

def remote-shell-command [command: string] {
  let escaped = ($command | str replace --all "'" "'\\''")
  $"sh -lc '($escaped)'"
}

def macos-keychain-secret [service: string, account: string = ""] {
  let args = if $account == "" {
    ["find-generic-password" "-w" "-s" $service]
  } else {
    ["find-generic-password" "-w" "-s" $service "-a" $account]
  }
  let result = (do { ^security ...$args } | complete)

  if $result.exit_code != 0 {
    let account_fragment = if $account == "" {
      ""
    } else {
      $" and account ($account)"
    }
    error make {
      msg: $"Failed to load macOS Keychain secret for service ($service)($account_fragment)."
    }
  }

  $result.stdout | str trim
}

def resolve-clean-secret [
  settings: record
  value_key: string
  keychain_service_key: string
  keychain_account_key: string
] {
  let explicit_value = (get-setting $settings $value_key "")
  if $explicit_value != "" {
    return $explicit_value
  }

  let keychain_service = (get-setting $settings $keychain_service_key "")
  if $keychain_service == "" {
    return ""
  }

  let keychain_account = (get-setting $settings $keychain_account_key "")
  macos-keychain-secret $keychain_service $keychain_account
}

def validate-codex-auth-json [auth_json: string] {
  let parsed = try {
    $auth_json | from json
  } catch {
    error make {
      msg: "Failed to parse Codex auth JSON."
    }
  }

  let auth_mode = ($parsed.auth_mode? | default "")
  let access_token = ($parsed.tokens.access_token? | default "")
  let refresh_token = ($parsed.tokens.refresh_token? | default "")

  if $auth_mode != "chatgpt" {
    error make {
      msg: $"Codex auth JSON must use ChatGPT auth mode, got ($auth_mode | default "<missing>")."
    }
  }

  if $access_token == "" or $refresh_token == "" {
    error make {
      msg: "Codex auth JSON is missing the ChatGPT token bundle."
    }
  }
}

def resolve-codex-auth-json [settings: record] {
  let configured_path = (get-setting $settings "SCRUBS_CODEX_AUTH_JSON_PATH" "")
  let candidate_path = if $configured_path == "" {
    ($env.HOME | path join ".codex" "auth.json")
  } else {
    $configured_path | path expand
  }

  if not ($candidate_path | path exists) {
    return ""
  }

  let auth_json = (open --raw $candidate_path)
  validate-codex-auth-json $auth_json
  $auth_json
}

def write-sealed-secret [secret_value: string, key_path: string, ciphertext_path: string] {
  let plaintext_path = $"($ciphertext_path).plain"

  $secret_value | save --force $plaintext_path
  ^chmod 600 $plaintext_path

  let encrypt_result = (
    do {
      ^openssl enc -aes-256-cbc -pbkdf2 -salt -pass $"file:($key_path)" -in $plaintext_path -out $ciphertext_path
    }
    | complete
  )
  rm -f $plaintext_path

  if $encrypt_result.exit_code != 0 {
    error make {
      msg: $"Failed to seal clean secret into ($ciphertext_path)."
    }
  }
}

def resolve-project-shim [projects_dir: string, shim_name: string] {
  let shim_dir = ($projects_dir | path join $shim_name)

  if ($shim_dir | path exists) {
    let guest_module = ($shim_dir | path join "guest.nix")
    let lima_config = ($shim_dir | path join "lima.yaml")
    let sandbox_definition = ($shim_dir | path join "sandbox-definition.sh")

    {
      source: $shim_dir
      guest_module: (if ($guest_module | path exists) { $guest_module } else { "" })
      lima_config: (if ($lima_config | path exists) { $lima_config } else { "" })
      sandbox_definition: (if ($sandbox_definition | path exists) { $sandbox_definition } else { "" })
    }
  } else {
    {
      source: ""
      guest_module: ""
      lima_config: ""
      sandbox_definition: ""
    }
  }
}

def main [
  instance_name: string
  --source-image(-s): string = ""
  --shim-name: string = ""
] {
  let repo_root = (repo-root)
  let vms_dir = (vms-dir)
  let settings = (load-settings)
  let default_working_image = ($repo_root | path join "vms" "images" "scrubs.qcow2")
  let cache_dir = (($env.TMPDIR? | default "/tmp") | path join "scrubs-lima")
  let payload_dir = ($cache_dir | path join "scrubs-bootstrap")
  let guest_apply = ($payload_dir | path join "guest-apply.sh")
  let template_file = ($vms_dir | path join "lima.local.yaml")
  let resolved_shim_name = if $shim_name == "" { $instance_name } else { $shim_name }
  let project_shim = (resolve-project-shim ($vms_dir | path join "projects") $resolved_shim_name)
  let instance_dir = ($env.HOME | path join ".lima" $instance_name)
  let current_user = (^id -un | str trim)
  let current_uid = (^id -u | str trim)
  let guest_user = (get-setting $settings "SCRUBS_GUEST_USER" $current_user)
  let guest_uid = (get-setting $settings "SCRUBS_GUEST_UID" $current_uid)
  let bootstrap_user = (get-setting $settings "SCRUBS_BOOTSTRAP_USER" $guest_user)
  let base_image = (
    if $source_image == "" {
      $default_working_image
    } else {
      $source_image
    }
  )
  let guest_arch = (get-setting $settings "SCRUBS_ARCH" "aarch64")
  let vm_type = (get-setting $settings "SCRUBS_VM_TYPE" "vz")
  let key_dir = ($vms_dir | path join "keys")
  let key_path = ($key_dir | path join "scrubs-dev")
  let start_timeout = (get-setting $settings "SCRUBS_START_TIMEOUT" "60s")
  mut ssh_port = (get-setting $settings "SCRUBS_SSH_PORT" "")
  mut host_port_3000 = (get-setting $settings "SCRUBS_HOST_PORT_3000" "")
  mut host_port_5173 = (get-setting $settings "SCRUBS_HOST_PORT_5173" "")
  mut host_port_8080 = (get-setting $settings "SCRUBS_HOST_PORT_8080" "")
  let host_resolver = (get-setting $settings "SCRUBS_HOST_RESOLVER" "true")
  let dns_servers = (get-setting $settings "SCRUBS_DNS" "")

  if $base_image == "" {
    error make {
      msg: $"Set --source-image or ensure the default working image exists at ($default_working_image). Use an OpenStack-compatible NixOS image with cloud-init support."
    }
  }

  let port_offset = if ($ssh_port == "" or $host_port_3000 == "" or $host_port_5173 == "" or $host_port_8080 == "") {
    if $instance_name == "scrubs-dev" {
      0
    } else {
      let instance_hash = (
        $instance_name
        | hash md5
        | str substring 0..7
        | into int --radix 16
      )
      (($instance_hash mod 1000) + 1)
    }
  } else {
    0
  }

  if $ssh_port == "" { $ssh_port = ((60022 + $port_offset) | into string) }
  if $host_port_3000 == "" { $host_port_3000 = ((3000 + $port_offset) | into string) }
  if $host_port_5173 == "" { $host_port_5173 = ((5173 + $port_offset) | into string) }
  if $host_port_8080 == "" { $host_port_8080 = ((8080 + $port_offset) | into string) }

  if $guest_arch not-in ["aarch64", "x86_64"] {
    error make { msg: $"Unsupported SCRUBS_ARCH: ($guest_arch). Use aarch64 or x86_64." }
  }

  if $vm_type not-in ["qemu", "vz"] {
    error make { msg: $"Unsupported SCRUBS_VM_TYPE: ($vm_type). Use qemu or vz." }
  }

  let mount_type = if $vm_type == "qemu" { "9p" } else { "virtiofs" }
  let ssh_args = (ssh-base-args $guest_user $ssh_port)
  let scp_args = (scp-base-args $ssh_port)

  rm -rf $payload_dir
  mkdir $cache_dir
  mkdir $key_dir
  mkdir ($payload_dir | path join "home" ".config" "nushell")
  mkdir ($payload_dir | path join "home" ".config" "mise")
  mkdir ($payload_dir | path join "home" ".local" "libexec" "scrubs")
  mkdir ($payload_dir | path join "home" ".local" "share" "scrubs" "clean-auth")
  mkdir ($payload_dir | path join "scrubs" "modules")
  mkdir ($payload_dir | path join "scrubs" "projects")

  if not ($key_path | path exists) {
    ^ssh-keygen -t ed25519 -N "" -f $key_path
  }

  let image_location = if (is-url $base_image) {
    $base_image
  } else {
    let expanded = ($base_image | path expand)
    if not ($expanded | path exists) {
      error make { msg: $"Base image not found: ($expanded)" }
    }
    $expanded
  }

  cp ($repo_root | path join "home" ".gitconfig") ($payload_dir | path join "home" ".gitconfig")
  cp ($repo_root | path join "home" ".config" "mise" "config.toml") ($payload_dir | path join "home" ".config" "mise" "config.toml")
  cp ($vms_dir | path join "templates" "profile") ($payload_dir | path join "home" ".profile")
  cp ($vms_dir | path join "templates" "bash_profile") ($payload_dir | path join "home" ".bash_profile")
  cp ($vms_dir | path join "templates" "bashrc") ($payload_dir | path join "home" ".bashrc")
  cp ($vms_dir | path join "templates" "install-dirty-tools.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "install-dirty-tools.sh")
  cp ($vms_dir | path join "templates" "dirty-exec.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "dirty-exec.sh")
  cp ($vms_dir | path join "templates" "mise-wrapper.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "mise-wrapper.sh")
  cp ($vms_dir | path join "templates" "clean-auth-lib.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "clean-auth-lib.sh")
  cp ($vms_dir | path join "templates" "gh-clean.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "gh-clean.sh")
  cp ($vms_dir | path join "templates" "codex-clean.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "codex-clean.sh")
  cp ($vms_dir | path join "templates" "sandbox-default-definition.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "sandbox-default-definition.sh")
  let sandbox_definition_source = if $project_shim.sandbox_definition == "" {
    ($vms_dir | path join "templates" "sandbox-definition.sh")
  } else {
    $project_shim.sandbox_definition
  }
  cp $sandbox_definition_source ($payload_dir | path join "home" ".local" "libexec" "scrubs" "sandbox-definition.sh")

  for file_name in [
    "carapace-init.nu"
    "config.nu"
    "config.shared.nu"
    "config.darwin.nu"
    "config.linux.nu"
    "env.nu"
    "env.shared.nu"
    "env.darwin.nu"
    "env.linux.nu"
    "kolo.nu"
    "ni-completions.nu"
    "vite-plus.nu"
  ] {
    cp ($repo_root | path join "home" ".config" "nushell" $file_name) ($payload_dir | path join "home" ".config" "nushell" $file_name)
  }

  cp ($vms_dir | path join "flake.nix") ($payload_dir | path join "scrubs" "flake.nix")
  cp ($vms_dir | path join "flake.lock") ($payload_dir | path join "scrubs" "flake.lock")
  cp ($vms_dir | path join "configuration.nix") ($payload_dir | path join "scrubs" "configuration.nix")
  cp ($vms_dir | path join "modules" "base.nix") ($payload_dir | path join "scrubs" "modules" "base.nix")
  cp ($vms_dir | path join "modules" "docker-shim.nix") ($payload_dir | path join "scrubs" "modules" "docker-shim.nix")

  let gh_token = (
    resolve-clean-secret
      $settings
      "SCRUBS_GH_TOKEN"
      "SCRUBS_GH_TOKEN_KEYCHAIN_SERVICE"
      "SCRUBS_GH_TOKEN_KEYCHAIN_ACCOUNT"
  )
  let codex_auth_json = (resolve-codex-auth-json $settings)
  let clean_secret_specs = [
    {
      name: "gh"
      ciphertext_file: "gh-token.enc"
      value: $gh_token
    }
    {
      name: "codex"
      ciphertext_file: "codex-auth.json.enc"
      value: $codex_auth_json
    }
  ]
  let enabled_clean_secrets = ($clean_secret_specs | where {|spec| $spec.value != "" })

  if not ($enabled_clean_secrets | is-empty) {
    let clean_auth_dir = ($payload_dir | path join "home" ".local" "share" "scrubs" "clean-auth")
    let seal_key_path = ($clean_auth_dir | path join "seal-key")

    ^openssl rand -base64 32 | save --force $seal_key_path
    ^chmod 600 $seal_key_path

    for spec in $enabled_clean_secrets {
      let ciphertext_path = ($clean_auth_dir | path join $spec.ciphertext_file)
      write-sealed-secret $spec.value $seal_key_path $ciphertext_path
      ^chmod 600 $ciphertext_path
    }

    let enabled_names = ($enabled_clean_secrets | get name | str join ", ")
    print $"Sealed clean auth for: ($enabled_names)"
  }

  if $project_shim.guest_module != "" {
    print $"Applying project shim from ($project_shim.source)"
    cp -r $project_shim.source ($payload_dir | path join "scrubs" "projects")
    $"
{ ... }:
{
  imports = [
    ../projects/($resolved_shim_name)/guest.nix
  ];
}
" | save --force ($payload_dir | path join "scrubs" "modules" "project-shim.nix")
  }

  let extra_lima_config = if $project_shim.lima_config == "" {
    {}
  } else {
    open --raw $project_shim.lima_config | from yaml
  }

  let unsupported_lima_keys = (
    $extra_lima_config
    | columns
    | where {|key| $key != "portForwards" }
  )

  if not ($unsupported_lima_keys | is-empty) {
    error make {
      msg: $"Unsupported keys in ($project_shim.lima_config): (($unsupported_lima_keys | str join ', ')). Only portForwards is supported."
    }
  }

  let extra_port_forwards = if (($extra_lima_config | get -o portForwards | default []) | is-empty) {
    ""
  } else {
    let extra_entries = (
      $extra_lima_config
      | get portForwards
      | to yaml
      | lines
      | each {|line| if $line == "" { "" } else { $"  ($line)" } }
      | str join "\n"
    )

    if $extra_entries == "" {
      ""
    } else {
      $"\n($extra_entries)"
    }
  }

  let repo_pubkey = (open --raw $"($key_path).pub" | str trim)
  $"
{ pkgs, ... }:
{
  _module.args.scrubsGuestUser = \"($guest_user)\";
  users.users = {
    \"($guest_user)\" = {
      isNormalUser = true;
      extraGroups = [ \"wheel\" ];
      shell = pkgs.bashInteractive;
      openssh.authorizedKeys.keys = [
        \"($repo_pubkey)\"
      ];
    };
  };
}
" | save --force ($payload_dir | path join "scrubs" "modules" "guest-user.nix")

  (
    open --raw ($vms_dir | path join "templates" "guest-apply.sh")
    | str replace --all "__SCRUBS_BOOTSTRAP_USER__" $bootstrap_user
  ) | save --force $guest_apply
  chmod +x $guest_apply

  let dns_block = if $dns_servers == "" {
    ""
  } else {
    let dns_entries = (
      $dns_servers
      | split row ","
      | each {|entry| $entry | str trim }
      | where {|entry| $entry != "" }
      | each {|entry| $"  - ($entry)" }
      | str join "\n"
    )
    $"dns:\n($dns_entries)"
  }

  (
    open --raw ($vms_dir | path join "lima.yaml")
    | str replace --all "REPLACE_WITH_BASE_IMAGE" $image_location
    | str replace --all "REPLACE_WITH_GUEST_USER" $guest_user
    | str replace --all "REPLACE_WITH_GUEST_UID" $guest_uid
    | str replace --all "REPLACE_WITH_ARCH" $guest_arch
    | str replace --all "REPLACE_WITH_VM_TYPE" $vm_type
    | str replace --all "REPLACE_WITH_MOUNT_TYPE" $mount_type
    | str replace --all "REPLACE_WITH_SSH_PORT" $ssh_port
    | str replace --all "REPLACE_WITH_HOST_RESOLVER" $host_resolver
    | str replace --all "REPLACE_WITH_HOST_PORT_3000" $host_port_3000
    | str replace --all "REPLACE_WITH_HOST_PORT_5173" $host_port_5173
    | str replace --all "REPLACE_WITH_HOST_PORT_8080" $host_port_8080
    | str replace --all "REPLACE_WITH_EXTRA_PORT_FORWARDS" $extra_port_forwards
    | str replace --all "REPLACE_WITH_DNS_BLOCK" $dns_block
  ) | save --force $template_file

  let instance_exists = ($instance_dir | path exists)
  let instance_config_file = ($instance_dir | path join "lima.yaml")
  if $instance_exists and ($instance_config_file | path exists) {
    let rendered_lima_config = (open --raw $template_file)
    let current_lima_config = (open --raw $instance_config_file)
    if $rendered_lima_config != $current_lima_config {
      print $"Refreshing Lima instance config at ($instance_config_file)"
      $rendered_lima_config | save --force $instance_config_file
    }
  }
  print $"Starting Lima instance ($instance_name)"
  print $"Lima start can take up to ($start_timeout); waiting for host startup output..."
  try {
    if $instance_exists {
      ^limactl start --timeout $start_timeout $instance_name
    } else {
      ^limactl start --yes --containerd=none --timeout $start_timeout --name $instance_name $template_file
    }
  } catch {
    print --stderr $"limactl start did not fully complete within ($start_timeout)."
    print --stderr "Continuing because scrubs only requires direct SSH reachability for bootstrap."
    print --stderr "If the next SSH and payload steps succeed, this Lima timeout can be treated as non-fatal for now."
  }

  print "Waiting for SSH access to the guest"
  mut ready = false
  for _ in 0..59 {
    let ssh_result = (do { ^ssh ...$ssh_args true } | complete)
    if $ssh_result.exit_code == 0 {
      $ready = true
      break
    }
    sleep 2sec
  }

  if not $ready {
    error make { msg: "Guest did not become reachable over SSH in time." }
  }

  let bootstrap_marker = "/var/lib/scrubs/bootstrap-complete"
  let already_bootstrapped = (
    (do { ^ssh ...$ssh_args (remote-shell-command $"test -f \"($bootstrap_marker)\"") } | complete).exit_code == 0
  )

  let bootstrap_home = $"/home/($bootstrap_user)"
  let bootstrap_dir = $"/home/($bootstrap_user)/scrubs-bootstrap"

  print "Copying scrubs payload into the guest"
  ^ssh ...$ssh_args (remote-shell-command $"rm -rf \"($bootstrap_dir)\"")
  ^ssh ...$ssh_args (remote-shell-command $"mkdir -p \"($bootstrap_dir)\"")
  ^scp ...$scp_args $"($payload_dir)/." $"($guest_user)@127.0.0.1:($bootstrap_dir)/"

  print "Applying scrubs base configuration inside the guest"
  ^ssh ...$ssh_args (remote-shell-command $"sh \"($bootstrap_dir)/guest-apply.sh\"")

  if $already_bootstrapped {
    print "Restarting the guest to activate the staged scrubs generation"
    ^limactl stop $instance_name
    print $"Lima start can take up to ($start_timeout); waiting for host startup output..."
    try {
      ^limactl start --timeout $start_timeout $instance_name
    } catch {
      print --stderr $"limactl start did not fully complete within ($start_timeout)."
      print --stderr "Continuing because scrubs only requires direct SSH reachability after the restart."
    }

    print "Waiting for SSH access to the restarted guest"
    $ready = false
    for _ in 0..59 {
      let ssh_result = (do { ^ssh ...$ssh_args true } | complete)
      if $ssh_result.exit_code == 0 {
        $ready = true
        break
      }
      sleep 2sec
    }

    if not $ready {
      error make { msg: "Guest did not become reachable over SSH after the restart." }
    }
  }

  print ""
  print "Scrubs guest is ready."
  print $"Use: limactl shell ($instance_name)"
  print "Nushell is installed in the guest; start it manually after login if you want it."
}
