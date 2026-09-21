#!/usr/bin/env nu

use ./lib.nu *

def main [
  --source-image(-s): string = ""
  --output-path(-o): string = ""
  --instance-name(-i): string = "scrubs-refresh"
] {
  let vms_dir = (vms-dir)
  let vm_type = ($env.SCRUBS_REFRESH_VM_TYPE? | default ($env.SCRUBS_VM_TYPE? | default "vz"))
  let guest_arch = ($env.SCRUBS_REFRESH_ARCH? | default ($env.SCRUBS_ARCH? | default "aarch64"))
  let delete_instance = (($env.SCRUBS_REFRESH_DELETE_INSTANCE? | default "true") | into string | str lowercase)
  let source = (if $source_image == "" { $vms_dir | path join "images" "scrubs.qcow2" } else { $source_image } | path expand)
  let output = (if $output_path == "" { $vms_dir | path join "images" "scrubs-next.qcow2" } else { $output_path } | path expand)
  let instance_dir = (lima-home | path join $instance_name)

  if not ($source | path exists) {
    error make { msg: $"Base image not found: ($source)" }
  }
  if ($output | path exists) or $output == $source {
    error make { msg: $"Refusing to overwrite ($output). Export a new candidate, validate it, then promote it." }
  }
  if ($instance_dir | path exists) {
    error make { msg: $"Lima instance ($instance_name) already exists. Refresh requires a new disposable instance." }
  }

  print $"Refreshing ($source) into candidate ($output)"
  with-env { SCRUBS_VM_TYPE: $vm_type, SCRUBS_ARCH: $guest_arch } {
    ^nu ($vms_dir | path join "bootstrap.nu") --for-base-image --source-image $source $instance_name tailscale-disabled
    if $env.LAST_EXIT_CODE != 0 {
      error make { msg: $"Base-image bootstrap failed. Maintenance instance ($instance_name) was retained for inspection." }
    }
  }

  ^nu ($vms_dir | path join "export-seed-image.nu") $instance_name $output
  if $env.LAST_EXIT_CODE != 0 {
    error make { msg: $"Base-image export failed. Maintenance instance ($instance_name) was retained for inspection." }
  }

  if $delete_instance == "true" {
    ^limactl delete $instance_name
    if $env.LAST_EXIT_CODE != 0 {
      error make { msg: $"Candidate exported, but temporary instance ($instance_name) could not be deleted." }
    }
  }

  print $"Candidate written to ($output). Validate a fresh guest before replacing scrubs.qcow2."
}
