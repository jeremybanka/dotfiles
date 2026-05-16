#!/usr/bin/env nu

use ./lib.nu *

def main [
  source_image: string
  output_path: string
  instance_name: string = "scrubs-refresh"
] {
  let scrubs_dir = (scrubs-dir)
  let vm_type = ($env.SCRUBS_REFRESH_VM_TYPE? | default ($env.SCRUBS_VM_TYPE? | default "vz"))
  let guest_arch = ($env.SCRUBS_REFRESH_ARCH? | default ($env.SCRUBS_ARCH? | default "aarch64"))
  let delete_instance = (($env.SCRUBS_REFRESH_DELETE_INSTANCE? | default "true") | into string | str downcase)
  let source_image = ($source_image | path expand)
  let output_path = ($output_path | path expand)

  if not ($source_image | path exists) {
    error make { msg: $"Base image not found: ($source_image)" }
  }

  if $source_image == $output_path {
    error make { msg: "Refusing to overwrite the source image in place. Write to a new path, then replace the old image after you validate it." }
  }

  print $"Refreshing base image from ($source_image)"
  print $"Using Lima instance ($instance_name) with vmType=($vm_type) arch=($guest_arch)"

  with-env {
    SCRUBS_VM_TYPE: $vm_type
    SCRUBS_ARCH: $guest_arch
  } {
    nu ($scrubs_dir | path join "bootstrap.nu") $source_image $instance_name
  }

  nu ($scrubs_dir | path join "export-seed-image.nu") $instance_name $output_path

  if $delete_instance == "true" {
    print $"Deleting temporary Lima instance ($instance_name)"
    do {
      ^limactl delete $instance_name
    } | complete | ignore
  }

  print $"Refreshed base image written to ($output_path)"
}
