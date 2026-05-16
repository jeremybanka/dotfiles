#!/usr/bin/env nu

use ./lib.nu *

def main [
  instance_name: string = "scrubs-dev"
] {
  let repo_root = (repo-root)
  let scrubs_dir = (scrubs-dir)
  let settings = (load-settings)
  let cache_dir = (($env.TMPDIR? | default "/tmp") | path join "scrubs-lima")
  let payload_dir = ($cache_dir | path join "scrubs-bootstrap")
  let guest_apply = ($payload_dir | path join "guest-apply.sh")
  let settings_file = ($scrubs_dir | path join "settings.env")
  let template_file = ($scrubs_dir | path join "lima.local.yaml")
  let current_user = (^id -un | str trim)
  let current_uid = (^id -u | str trim)
  let guest_user = (get-setting $settings "SCRUBS_GUEST_USER" $current_user)
  let guest_uid = (get-setting $settings "SCRUBS_GUEST_UID" $current_uid)
  let bootstrap_user = (get-setting $settings "SCRUBS_BOOTSTRAP_USER" $guest_user)
  let base_image = (get-setting $settings "SCRUBS_BASE_IMAGE" "")
  let guest_arch = (get-setting $settings "SCRUBS_ARCH" "aarch64")
  let vm_type = (get-setting $settings "SCRUBS_VM_TYPE" "vz")
  let key_dir = ($scrubs_dir | path join "keys")
  let key_path = ($key_dir | path join "scrubs-dev")
  let start_timeout = (get-setting $settings "SCRUBS_START_TIMEOUT" "90s")
  mut ssh_port = (get-setting $settings "SCRUBS_SSH_PORT" "")
  mut host_port_3000 = (get-setting $settings "SCRUBS_HOST_PORT_3000" "")
  mut host_port_5173 = (get-setting $settings "SCRUBS_HOST_PORT_5173" "")
  mut host_port_8080 = (get-setting $settings "SCRUBS_HOST_PORT_8080" "")
  let host_resolver = (get-setting $settings "SCRUBS_HOST_RESOLVER" "true")
  let dns_servers = (get-setting $settings "SCRUBS_DNS" "")

  if $base_image == "" {
    error make {
      msg: $"Set SCRUBS_BASE_IMAGE in the environment or ($settings_file). Use an OpenStack-compatible NixOS image with cloud-init support."
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

  rm -rf $payload_dir
  mkdir $cache_dir
  mkdir $key_dir
  mkdir ($payload_dir | path join "home" ".config" "nushell")
  mkdir ($payload_dir | path join "home" ".config" "mise")
  mkdir ($payload_dir | path join "lima" "nixos" "modules")

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

  for file_name in [
    "config.nu"
    "config.shared.nu"
    "config.darwin.nu"
    "config.linux.nu"
    "env.nu"
    "env.shared.nu"
    "env.darwin.nu"
    "env.linux.nu"
    "kolo.nu"
    "mise.nu"
    "ni-completions.nu"
    "vite-plus.nu"
  ] {
    cp
      ($repo_root | path join "home" ".config" "nushell" $file_name)
      ($payload_dir | path join "home" ".config" "nushell" $file_name)
  }

  cp ($scrubs_dir | path join "flake.nix") ($payload_dir | path join "lima" "nixos" "flake.nix")
  cp ($scrubs_dir | path join "flake.lock") ($payload_dir | path join "lima" "nixos" "flake.lock")
  cp ($scrubs_dir | path join "configuration.nix") ($payload_dir | path join "lima" "nixos" "configuration.nix")
  cp ($scrubs_dir | path join "modules" "base.nix") ($payload_dir | path join "lima" "nixos" "modules" "base.nix")

  let repo_pubkey = (open --raw $"($key_path).pub" | str trim)
  $"
{ pkgs, ... }:
{
  users.users = {
    \"($guest_user)\" = {
      isNormalUser = true;
      extraGroups = [ \"wheel\" ];
      shell = pkgs.nushell;
      openssh.authorizedKeys.keys = [
        \"($repo_pubkey)\"
      ];
    };
  };
}
" | save --force ($payload_dir | path join "lima" "nixos" "modules" "guest-user.nix")

  $"
#!/bin/sh
set -eu

payload=\"\$HOME/scrubs-bootstrap\"

mkdir -p \"\$HOME/.config/nushell\" \"\$HOME/.config/mise\"
cp \"\$payload/home/.gitconfig\" \"\$HOME/.gitconfig\"
cp \"\$payload/home/.config/mise/config.toml\" \"\$HOME/.config/mise/config.toml\"
cp \"\$payload/home/.config/nushell/\"* \"\$HOME/.config/nushell/\"
cp /etc/nixos/hardware-configuration.nix \"\$payload/lima/nixos/modules/runtime-hardware.nix\"

if ! sudo -n true >/dev/null 2>&1; then
  echo \"Guest user '($bootstrap_user)' needs passwordless sudo for bootstrap.\" >&2
  echo \"Grant sudo in the base image or rerun manually inside the guest.\" >&2
  exit 1
fi

sudo nixos-rebuild switch --flake \"\$payload/lima/nixos#scrubs-base\"
" | save --force $guest_apply
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
    open --raw ($scrubs_dir | path join "lima.yaml")
    | str replace "REPLACE_WITH_BASE_IMAGE" $image_location
    | str replace "REPLACE_WITH_GUEST_USER" $guest_user
    | str replace "REPLACE_WITH_GUEST_UID" $guest_uid
    | str replace "REPLACE_WITH_ARCH" $guest_arch
    | str replace "REPLACE_WITH_VM_TYPE" $vm_type
    | str replace "REPLACE_WITH_MOUNT_TYPE" $mount_type
    | str replace "REPLACE_WITH_SSH_PORT" $ssh_port
    | str replace "REPLACE_WITH_HOST_RESOLVER" $host_resolver
    | str replace "REPLACE_WITH_HOST_PORT_3000" $host_port_3000
    | str replace "REPLACE_WITH_HOST_PORT_5173" $host_port_5173
    | str replace "REPLACE_WITH_HOST_PORT_8080" $host_port_8080
    | str replace "REPLACE_WITH_DNS_BLOCK" $dns_block
  ) | save --force $template_file

  print $"Starting Lima instance ($instance_name)"
  let start_result = (do { ^limactl start --containerd=none --timeout $start_timeout --name $instance_name $template_file } | complete)
  if $start_result.exit_code != 0 {
    print --stderr $"limactl start did not fully complete within ($start_timeout)."
    print --stderr "Continuing because scrubs only requires SSH reachability for bootstrap."
  }

  print "Waiting for SSH access to the guest"
  mut ready = false
  for _ in 0..59 {
    let shell_result = (do { ^limactl shell $instance_name true } | complete)
    if $shell_result.exit_code == 0 {
      $ready = true
      break
    }
    sleep 2sec
  }

  if not $ready {
    error make { msg: "Guest did not become reachable over SSH in time." }
  }

  let bootstrap_home = $"/home/($bootstrap_user)"

  print "Copying scrubs payload into the guest"
  ^limactl shell $instance_name rm -rf $"/home/($bootstrap_user)/scrubs-bootstrap"
  ^limactl shell $instance_name mkdir -p $"/home/($bootstrap_user)/scrubs-bootstrap"
  ^limactl copy --backend=scp -r $"($payload_dir)/." $'($instance_name):($bootstrap_home)/scrubs-bootstrap/'

  print "Applying scrubs base configuration inside the guest"
  ^limactl shell $instance_name sh $"/home/($bootstrap_user)/scrubs-bootstrap/guest-apply.sh"

  print "Scrubs guest is ready."
  print $"Use: limactl shell ($instance_name)"
}
