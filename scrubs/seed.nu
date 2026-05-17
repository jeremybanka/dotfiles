#!/usr/bin/env nu

use ./lib.nu *

def main [
  instance_name: string = "scrubs-seed"
] {
  let scrubs_dir = (scrubs-dir)
  let settings = (load-settings)
  let seed_dir = ($scrubs_dir | path join "seed")
  let template_file = ($scrubs_dir | path join "seed.local.yaml")
  let existing_iso = ($env.HOME | path join ".lima" $instance_name "iso")
  let arch = (get-setting $settings "SCRUBS_SEED_ARCH" "aarch64")
  let flavor = (get-setting $settings "SCRUBS_SEED_FLAVOR" "minimal")
  let default_cache_iso = (
    $env.HOME
    | path join "Library" "Caches" "scrubs" $"nixos-($flavor)-($arch).iso"
  )
  mut seed_iso = (get-setting $settings "SCRUBS_SEED_ISO" "")

  if $seed_iso == "" {
    $seed_iso = $default_cache_iso
  } else {
    $seed_iso = (expand-home $seed_iso)
  }

  if $seed_iso == "" {
    error make { msg: "Set SCRUBS_SEED_ISO in the environment or scrubs/settings.env." }
  }

  let iso_location = if ($existing_iso | path exists) {
    print $"Reusing local installer ISO at ($existing_iso)"
    $existing_iso
  } else if (is-url $seed_iso) {
    $seed_iso
  } else {
    let expanded = ($seed_iso | path expand)
    if not ($expanded | path exists) {
      error make { msg: $"Seed ISO not found: ($expanded)" }
    }
    $expanded
  }

  (
    open --raw ($scrubs_dir | path join "seed.yaml")
    | str replace "REPLACE_WITH_SEED_ISO" $iso_location
    | str replace "REPLACE_WITH_SEED_DIR" $seed_dir
  ) | save --force $template_file

  print $"Starting installer instance ($instance_name)"
  ^limactl start --name $instance_name --video $template_file

  print ""
  print "Inside the installer console, run:"
  print "  sudo -i"
  print "  /mnt/host-scrubs-seed/install.sh"
  print ""
  print "When installation completes, shut the guest down from inside NixOS."
  print "Then export the reusable base image with:"
  print $"  just export-seed-image ($instance_name) /absolute/path/to/nixos-base-aarch64.qcow2"
}
