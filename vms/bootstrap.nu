#!/usr/bin/env nu

use ./lib.nu *
use ./templates/sandbox-policy-lib.nu *

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

def macos-keychain-secret-optional [service: string, account: string = ""] {
  let args = if $account == "" {
    ["find-generic-password" "-w" "-s" $service]
  } else {
    ["find-generic-password" "-w" "-s" $service "-a" $account]
  }
  let result = (do { ^security ...$args } | complete)

  if $result.exit_code != 0 {
    return ""
  }

  $result.stdout | str trim
}

def has-setting [settings: record, key: string] {
  if ($env | columns | any {|column| $column == $key }) {
    true
  } else {
    $settings | columns | any {|column| $column == $key }
  }
}

def normalize-clean-auth-profile-suffix [profile_name: string] {
  let normalized = (
    $profile_name
    | str trim
    | str upcase
    | str replace --regex --all '[^A-Z0-9]+' "_"
    | str replace --regex '^_+' ""
    | str replace --regex '_+$' ""
  )

  if $normalized == "" {
    error make {
      msg: $"Clean auth profile name '($profile_name)' does not contain any letters or numbers."
    }
  }

  $normalized
}

def resolve-clean-auth-profile [settings: record, explicit_profile: string] {
  let selected_profile = if $explicit_profile == "" {
    get-setting $settings "SCRUBS_CLEAN_AUTH_PROFILE" "personal"
  } else {
    $explicit_profile
  }
  let trimmed_profile = ($selected_profile | str trim)

  if $trimmed_profile == "" {
    return {
      name: ""
      suffix: ""
    }
  }

  {
    name: $trimmed_profile
    suffix: (normalize-clean-auth-profile-suffix $trimmed_profile)
  }
}

def get-profiled-setting [
  settings: record
  base_key: string
  profile_suffix: string
  default_value: any = null
] {
  if $profile_suffix != "" {
    let profiled_key = $"($base_key)__($profile_suffix)"
    if (has-setting $settings $profiled_key) {
      return (get-setting $settings $profiled_key $default_value)
    }
  }

  get-setting $settings $base_key $default_value
}

def default-github-keychain-service [profile_name: string] {
  $"scrubs-gh-token-($profile_name)"
}

def default-tailscale-oauth-keychain-service [profile_name: string] {
  if $profile_name == "" {
    "scrubs-tailscale-oauth-secret"
  } else {
    $"scrubs-tailscale-oauth-secret-($profile_name)"
  }
}

def resolve-github-token [settings: record, profile_name: string, profile_suffix: string] {
  let explicit_value = (get-profiled-setting $settings "SCRUBS_GH_TOKEN" $profile_suffix "")
  if $explicit_value != "" {
    return $explicit_value
  }

  let profiled_service_key = $"SCRUBS_GH_TOKEN_KEYCHAIN_SERVICE__($profile_suffix)"
  let profiled_account_key = $"SCRUBS_GH_TOKEN_KEYCHAIN_ACCOUNT__($profile_suffix)"

  let has_profiled_service = (has-setting $settings $profiled_service_key)
  let has_profiled_account = (has-setting $settings $profiled_account_key)

  if $profile_suffix != "" and $has_profiled_service {
    let profiled_service = (get-setting $settings $profiled_service_key (default-github-keychain-service $profile_name))
    let profiled_account = (get-setting $settings $profiled_account_key "github.com")
    return (macos-keychain-secret $profiled_service $profiled_account)
  }

  if $profile_suffix != "" and $has_profiled_account {
    let profiled_service = (get-setting $settings $profiled_service_key (default-github-keychain-service $profile_name))
    let profiled_account = (get-setting $settings $profiled_account_key "github.com")
    return (macos-keychain-secret $profiled_service $profiled_account)
  }

  if $profile_name != "" {
    let conventional_service = (default-github-keychain-service $profile_name)
    let conventional_token = (macos-keychain-secret-optional $conventional_service "github.com")
    if $conventional_token != "" {
      return $conventional_token
    }
  }

  let legacy_service = (get-setting $settings "SCRUBS_GH_TOKEN_KEYCHAIN_SERVICE" "")
  if $legacy_service == "" {
    return ""
  }

  let legacy_account = (get-setting $settings "SCRUBS_GH_TOKEN_KEYCHAIN_ACCOUNT" "github.com")
  macos-keychain-secret $legacy_service $legacy_account
}

def resolve-tailscale-oauth-secret [settings: record] {
  let explicit_value = (get-setting $settings "SCRUBS_TAILSCALE_OAUTH_SECRET" "")
  if $explicit_value != "" {
    return $explicit_value
  }

  let deprecated_explicit_value = (get-setting $settings "SCRUBS_TAILSCALE_OAUTH_SECRET__PERSONAL" "")
  if $deprecated_explicit_value != "" {
    return $deprecated_explicit_value
  }

  let default_service = (get-setting $settings "SCRUBS_TAILSCALE_OAUTH_SECRET_KEYCHAIN_SERVICE" "scrubs-tailscale-oauth-secret")
  let default_account = (get-setting $settings "SCRUBS_TAILSCALE_OAUTH_SECRET_KEYCHAIN_ACCOUNT" "tailscale")
  let default_secret = (macos-keychain-secret-optional $default_service $default_account)
  if $default_secret != "" {
    return $default_secret
  }

  # Accept the old profile-scoped Tailscale settings as a migration path, but
  # keep Tailscale itself on a single global auth source.
  let deprecated_profiled_service_key = "SCRUBS_TAILSCALE_OAUTH_SECRET_KEYCHAIN_SERVICE__PERSONAL"
  let deprecated_profiled_account_key = "SCRUBS_TAILSCALE_OAUTH_SECRET_KEYCHAIN_ACCOUNT__PERSONAL"
  if (has-setting $settings $deprecated_profiled_service_key) or (has-setting $settings $deprecated_profiled_account_key) {
    let deprecated_service = (get-setting $settings $deprecated_profiled_service_key "scrubs-tailscale-oauth-secret-personal")
    let deprecated_account = (get-setting $settings $deprecated_profiled_account_key "tailscale")
    let deprecated_secret = (macos-keychain-secret-optional $deprecated_service $deprecated_account)
    if $deprecated_secret != "" {
      return $deprecated_secret
    }
  }

  let deprecated_conventional_secret = (macos-keychain-secret-optional "scrubs-tailscale-oauth-secret-personal" "tailscale")
  if $deprecated_conventional_secret != "" {
    return $deprecated_conventional_secret
  }

  let legacy_explicit_value = (get-setting $settings "SCRUBS_TAILSCALE_AUTH_KEY" "")
  if $legacy_explicit_value != "" {
    return $legacy_explicit_value
  }

  let deprecated_legacy_explicit_value = (get-setting $settings "SCRUBS_TAILSCALE_AUTH_KEY__PERSONAL" "")
  if $deprecated_legacy_explicit_value != "" {
    return $deprecated_legacy_explicit_value
  }

  let legacy_default_service = (get-setting $settings "SCRUBS_TAILSCALE_AUTH_KEYCHAIN_SERVICE" "scrubs-tailscale-auth-key")
  let legacy_default_account = (get-setting $settings "SCRUBS_TAILSCALE_AUTH_KEYCHAIN_ACCOUNT" "tailscale")
  let legacy_default_secret = (macos-keychain-secret-optional $legacy_default_service $legacy_default_account)
  if $legacy_default_secret != "" {
    return $legacy_default_secret
  }

  let deprecated_legacy_profiled_service_key = "SCRUBS_TAILSCALE_AUTH_KEYCHAIN_SERVICE__PERSONAL"
  let deprecated_legacy_profiled_account_key = "SCRUBS_TAILSCALE_AUTH_KEYCHAIN_ACCOUNT__PERSONAL"
  if (has-setting $settings $deprecated_legacy_profiled_service_key) or (has-setting $settings $deprecated_legacy_profiled_account_key) {
    let deprecated_legacy_service = (get-setting $settings $deprecated_legacy_profiled_service_key "scrubs-tailscale-auth-key-personal")
    let deprecated_legacy_account = (get-setting $settings $deprecated_legacy_profiled_account_key "tailscale")
    let deprecated_legacy_secret = (macos-keychain-secret-optional $deprecated_legacy_service $deprecated_legacy_account)
    if $deprecated_legacy_secret != "" {
      return $deprecated_legacy_secret
    }
  }

  macos-keychain-secret-optional "scrubs-tailscale-auth-key-personal" "tailscale"
}

def resolve-clean-secret [
  settings: record
  profile_suffix: string
  value_key: string
  keychain_service_key: string
  keychain_account_key: string
] {
  let explicit_value = (get-profiled-setting $settings $value_key $profile_suffix "")
  if $explicit_value != "" {
    return $explicit_value
  }

  let keychain_service = (get-profiled-setting $settings $keychain_service_key $profile_suffix "")
  if $keychain_service == "" {
    return ""
  }

  let keychain_account = (get-profiled-setting $settings $keychain_account_key $profile_suffix "")
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

def resolve-codex-auth-json [settings: record, profile_suffix: string] {
  let configured_path = (get-profiled-setting $settings "SCRUBS_CODEX_AUTH_JSON_PATH" $profile_suffix "")
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

def normalize-tailscale-hostname [instance_name: string] {
  let normalized = (
    $instance_name
    | str trim
    | str downcase
    | str replace --regex --all '[^a-z0-9-]+' "-"
    | str replace --regex '^-+' ""
    | str replace --regex '-+$' ""
  )

  if $normalized == "" {
    error make {
      msg: $"Instance name '($instance_name)' cannot be converted into a Tailscale hostname."
    }
  }

  if (($normalized | str length) > 63) {
    error make {
      msg: $"Tailscale hostname '($normalized)' derived from instance name '($instance_name)' is longer than 63 characters."
    }
  }

  $normalized
}

def resolve-tailscale-tags [settings: record] {
  let tags = (get-setting $settings "SCRUBS_TAILSCALE_TAGS" "tag:scrubs")
  let trimmed = ($tags | str trim)
  if $trimmed == "" {
    error make {
      msg: "SCRUBS_TAILSCALE_TAGS cannot be empty when Tailscale OAuth bootstrap is enabled."
    }
  }
  $trimmed
}

def resolve-tailscale-preauthorized [settings: record] {
  let configured = (get-setting $settings "SCRUBS_TAILSCALE_PREAUTHORIZED" "true")
  let normalized = ($configured | into string | str trim | str downcase)
  $normalized in ["1", "true", "yes", "on"]
}

def resolve-tailscale-ephemeral [settings: record] {
  let configured = (get-setting $settings "SCRUBS_TAILSCALE_EPHEMERAL" "false")
  let normalized = ($configured | into string | str trim | str downcase)
  $normalized in ["1", "true", "yes", "on"]
}

def resolve-tailscale-bootstrap-mode [tailscale_mode: string] {
  let normalized = ($tailscale_mode | str trim | str downcase)

  if $normalized not-in ["tailscale-enabled", "tailscale-disabled"] {
    error make {
      msg: $"Unsupported Tailscale bootstrap mode '($tailscale_mode)'. Use tailscale-enabled or tailscale-disabled."
    }
  }

  $normalized
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
    let sandbox_policy = ($shim_dir | path join "sandbox-policy.nuon")
    let sandbox_definition = ($shim_dir | path join "sandbox-definition.sh")

    {
      source: $shim_dir
      guest_module: (if ($guest_module | path exists) { $guest_module } else { "" })
      lima_config: (if ($lima_config | path exists) { $lima_config } else { "" })
      sandbox_policy: (if ($sandbox_policy | path exists) { $sandbox_policy } else { "" })
      sandbox_definition: (if ($sandbox_definition | path exists) { $sandbox_definition } else { "" })
    }
  } else {
    {
      source: ""
      guest_module: ""
      lima_config: ""
      sandbox_policy: ""
      sandbox_definition: ""
    }
  }
}

def main [
  instance_name: string
  --source-image(-s): string = ""
  --shim-name: string = ""
  --clean-auth-profile(-p): string = ""
  tailscale_mode: string = "tailscale-enabled"
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
  let selected_clean_auth_profile = (resolve-clean-auth-profile $settings $clean_auth_profile)
  let resolved_tailscale_mode = (resolve-tailscale-bootstrap-mode $tailscale_mode)
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
  cp ($repo_root | path join "home" ".gitignore_global") ($payload_dir | path join "home" ".gitignore_global")
  cp ($repo_root | path join "home" ".config" "mise" "config.toml") ($payload_dir | path join "home" ".config" "mise" "config.toml")
  cp ($vms_dir | path join "templates" "profile") ($payload_dir | path join "home" ".profile")
  cp ($vms_dir | path join "templates" "bash_profile") ($payload_dir | path join "home" ".bash_profile")
  cp ($vms_dir | path join "templates" "bashrc") ($payload_dir | path join "home" ".bashrc")
  cp ($vms_dir | path join "templates" "install-dirty-tools.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "install-dirty-tools.sh")
  cp ($vms_dir | path join "templates" "install-dirty-tools-legacy.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "install-dirty-tools-legacy.sh")
  cp ($vms_dir | path join "templates" "install-dirty-tools.nu") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "install-dirty-tools.nu")
  cp ($vms_dir | path join "templates" "sandbox-policy-lib.nu") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "sandbox-policy-lib.nu")
  cp ($vms_dir | path join "templates" "dirty-exec.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "dirty-exec.sh")
  cp ($vms_dir | path join "templates" "mise-wrapper.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "mise-wrapper.sh")
  cp ($vms_dir | path join "templates" "clean-auth-lib.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "clean-auth-lib.sh")
  cp ($vms_dir | path join "templates" "gh-clean.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "gh-clean.sh")
  cp ($vms_dir | path join "templates" "codex-clean.sh") ($payload_dir | path join "home" ".local" "libexec" "scrubs" "codex-clean.sh")
  let default_sandbox_policy = ($vms_dir | path join "templates" "sandbox-default-policy.nuon")
  cp $default_sandbox_policy ($payload_dir | path join "home" ".local" "libexec" "scrubs" "sandbox-default-policy.nuon")
  render-sandbox-definition (load-sandbox-policy $default_sandbox_policy) | save --force ($payload_dir | path join "home" ".local" "libexec" "scrubs" "sandbox-default-definition.sh")
  let sandbox_policy_source = if $project_shim.sandbox_policy == "" {
    $default_sandbox_policy
  } else {
    $project_shim.sandbox_policy
  }
  let sandbox_policy_mode = if $project_shim.sandbox_policy != "" or $project_shim.sandbox_definition == "" {
    "nuon"
  } else {
    "legacy-shell"
  }
  cp $sandbox_policy_source ($payload_dir | path join "home" ".local" "libexec" "scrubs" "sandbox-policy.nuon")
  if $sandbox_policy_mode == "nuon" {
    render-sandbox-definition (load-sandbox-policy $sandbox_policy_source) | save --force ($payload_dir | path join "home" ".local" "libexec" "scrubs" "sandbox-definition.sh")
  } else {
    cp $project_shim.sandbox_definition ($payload_dir | path join "home" ".local" "libexec" "scrubs" "sandbox-definition.sh")
  }
  $sandbox_policy_mode | save --force ($payload_dir | path join "home" ".local" "libexec" "scrubs" "sandbox-policy-mode")

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
  for module_path in (ls ($vms_dir | path join "modules") | where type == file | get name | where ($it | str ends-with ".nix")) {
    cp $module_path ($payload_dir | path join "scrubs" "modules" ($module_path | path basename))
  }

  let gh_token = (resolve-github-token $settings $selected_clean_auth_profile.name $selected_clean_auth_profile.suffix)
  let codex_auth_json = (resolve-codex-auth-json $settings $selected_clean_auth_profile.suffix)
  let tailscale_enabled = ($resolved_tailscale_mode == "tailscale-enabled")
  let tailscale_oauth_secret = if $tailscale_enabled {
    (resolve-tailscale-oauth-secret $settings)
  } else {
    ""
  }
  let tailscale_tags = if $tailscale_oauth_secret == "" { "" } else { resolve-tailscale-tags $settings }
  let tailscale_preauthorized = if $tailscale_oauth_secret == "" { false } else { resolve-tailscale-preauthorized $settings }
  let tailscale_ephemeral = if $tailscale_oauth_secret == "" { false } else { resolve-tailscale-ephemeral $settings }
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
    {
      name: "tailscale"
      ciphertext_file: "tailscale-oauth-secret.enc"
      value: $tailscale_oauth_secret
    }
  ]
  let enabled_clean_secrets = ($clean_secret_specs | where {|spec| $spec.value != "" })

  if $selected_clean_auth_profile.name != "" {
    print $"Selected clean auth profile: ($selected_clean_auth_profile.name)"
  }

  if not $tailscale_enabled {
    print "Tailscale bootstrap mode: disabled"
  }

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
    let profile_fragment = if $selected_clean_auth_profile.name == "" {
      ""
    } else {
      " (profile: " + $selected_clean_auth_profile.name + ")"
    }
    print $"Sealed clean auth for: ($enabled_names)($profile_fragment)"
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

  if $tailscale_oauth_secret != "" {
    let tailscale_hostname = (normalize-tailscale-hostname $instance_name)
    let clean_auth_dir = $"/home/($guest_user)/.local/share/scrubs/clean-auth"
    let tailscale_ciphertext_path = $clean_auth_dir + "/tailscale-oauth-secret.enc"
    let tailscale_seal_key_path = $clean_auth_dir + "/seal-key"
    $"
{ lib, pkgs, ... }:
let
  scrubsTailscaleRuntimeDir = \"/run/scrubs-clean-auth\";
  scrubsTailscaleRuntimeKey = scrubsTailscaleRuntimeDir + \"/tailscale-oauth-secret\";
in
{
  services.tailscale = {
    enable = true;
    authKeyFile = scrubsTailscaleRuntimeKey;
    authKeyParameters = {
      ephemeral = (if $tailscale_ephemeral { "true" } else { "false" });
      preauthorized = (if $tailscale_preauthorized { "true" } else { "false" });
    };
    extraUpFlags = [
      \"--accept-dns=false\"
      \"--hostname=($tailscale_hostname)\"
      \"--advertise-tags=($tailscale_tags)\"
      \"--ssh\"
    ];
  };

  systemd.tmpfiles.rules = [
    \"d /run/scrubs-clean-auth 0700 root root -\"
  ];

  systemd.services.scrubs-materialize-tailscale-auth = {
    description = \"Materialize the sealed Tailscale OAuth secret for scrubs\";
    before = [ \"tailscaled-autoconnect.service\" ];
    requiredBy = [ \"tailscaled-autoconnect.service\" ];
    serviceConfig = {
      Type = \"oneshot\";
      RemainAfterExit = true;
      UMask = \"0077\";
    };
    script = ''
      runtime_dir=${lib.escapeShellArg scrubsTailscaleRuntimeDir}
      runtime_key=${lib.escapeShellArg scrubsTailscaleRuntimeKey}
      seal_key=${lib.escapeShellArg \"($tailscale_seal_key_path)\"}
      ciphertext=${lib.escapeShellArg \"($tailscale_ciphertext_path)\"}

      ${pkgs.coreutils}/bin/install -d -m 700 \"$runtime_dir\"
      ${pkgs.openssl}/bin/openssl enc -d -aes-256-cbc -pbkdf2 -pass \"file:$seal_key\" -in \"$ciphertext\" -out \"$runtime_key\"
      ${pkgs.coreutils}/bin/chmod 600 \"$runtime_key\"
    '';
  };

  # tailscaled-autoconnect can race systemd-resolved during early boot on Lima.
  systemd.services.tailscaled-autoconnect = {
    after = [
      \"network-online.target\"
      \"systemd-resolved.service\"
      \"nss-lookup.target\"
    ];
    wants = [
      \"network-online.target\"
      \"systemd-resolved.service\"
      \"nss-lookup.target\"
    ];
    serviceConfig = {
      Restart = \"on-failure\";
      RestartSec = \"5s\";
    };
  };

  systemd.services.scrubs-clear-tailscale-auth = {
    description = \"Remove the materialized Tailscale OAuth secret after autoconnect\";
    after = [ \"tailscaled-autoconnect.service\" ];
    requires = [ \"tailscaled-autoconnect.service\" ];
    wantedBy = [ \"multi-user.target\" ];
    serviceConfig = {
      Type = \"oneshot\";
    };
    script = ''
      ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg scrubsTailscaleRuntimeKey}
    '';
  };
}
" | save --force ($payload_dir | path join "scrubs" "modules" "tailscale-config.nix")
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
      | each {|line| if $line == "" { "" } else { "  " + $line } }
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
      | each {|entry| "  - " + $entry }
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

  let bootstrap_home = $"/home/($bootstrap_user)"
  let bootstrap_dir = $"/home/($bootstrap_user)/scrubs-bootstrap"

  print "Copying scrubs payload into the guest"
  ^ssh ...$ssh_args (remote-shell-command $"rm -rf \"($bootstrap_dir)\"")
  ^ssh ...$ssh_args (remote-shell-command $"mkdir -p \"($bootstrap_dir)\"")
  ^scp ...$scp_args $"($payload_dir)/." $"($guest_user)@127.0.0.1:($bootstrap_dir)/"

  print "Applying scrubs base configuration inside the guest"
  ^ssh ...$ssh_args (remote-shell-command $"sh \"($bootstrap_dir)/guest-apply.sh\"")

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

  print ""
  print "Scrubs guest is ready."
  print $"Use: limactl shell ($instance_name)"
  print "Nushell is installed in the guest; start it manually after login if you want it."
}
