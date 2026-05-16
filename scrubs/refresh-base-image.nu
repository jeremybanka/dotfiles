#!/usr/bin/env nu

use ./lib.nu *

def main [
  source_image_arg: string = ""
  output_path_arg: string = ""
  instance_name: string = "scrubs-refresh"
] {
  let scrubs_dir = (scrubs-dir)
  let repo_root = (repo-root)
  let vm_type = ($env.SCRUBS_REFRESH_VM_TYPE? | default ($env.SCRUBS_VM_TYPE? | default "vz"))
  let guest_arch = ($env.SCRUBS_REFRESH_ARCH? | default ($env.SCRUBS_ARCH? | default "aarch64"))
  let delete_instance = (($env.SCRUBS_REFRESH_DELETE_INSTANCE? | default "true") | into string | str downcase)
  let default_working_image = ($repo_root | path join "scrubs" "qcow2" "scrubs.qcow2")
  let source_image = (
    if $source_image_arg == "" {
      $default_working_image
    } else {
      $source_image_arg
    }
    | path expand
  )
  let output_path = (
    if $output_path_arg == "" {
      $source_image
    } else {
      $output_path_arg | path expand
    }
  )
  let replace_in_place = ($source_image == $output_path)
  let output_name = ($output_path | path basename)

  if not ($source_image | path exists) {
    error make { msg: $"Base image not found: ($source_image)" }
  }

  let export_path = if $replace_in_place {
    let output_dir = ($output_path | path dirname)
    let temp_path = if $output_name == "scrubs.qcow2" {
      $output_dir | path join "scrubs.qcow2.tmp"
    } else {
      $output_dir | path join $"($output_name).tmp"
    }
    if ($temp_path | path exists) {
      rm --force $temp_path
    }
    $temp_path
  } else {
    $output_path
  }

  print $"Refreshing base image from ($source_image)"
  print $"Using Lima instance ($instance_name) with vmType=($vm_type) arch=($guest_arch)"
  if $replace_in_place {
    print $"Exporting through temporary image ($export_path) before replacing ($output_path)"
  }

  with-env {
    SCRUBS_VM_TYPE: $vm_type
    SCRUBS_ARCH: $guest_arch
  } {
    nu ($scrubs_dir | path join "bootstrap.nu") $source_image $instance_name
  }

  try {
    nu ($scrubs_dir | path join "export-seed-image.nu") $instance_name $export_path

    if $replace_in_place {
      print $"Replacing working base image at ($output_path)"
      mv --force $export_path $output_path
    }
  } catch {|err|
    if $replace_in_place and ($export_path | path exists) {
      rm --force $export_path
    }
    error make {
      msg: $"Failed to refresh base image: ($err.msg)"
    }
  }

  if $delete_instance == "true" {
    print $"Deleting temporary Lima instance ($instance_name)"
    do {
      ^limactl delete $instance_name
    } | complete | ignore
  }

  print $"Refreshed base image written to ($output_path)"
}
