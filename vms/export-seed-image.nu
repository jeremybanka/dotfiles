#!/usr/bin/env nu

use ./lib.nu *

# Export is destructive to guest-local data. Use a disposable seed/refresh VM.
def main [
  instance_name: string
  output_path: string
] {
  let instance_dir = (lima-home | path join $instance_name)
  let disk_path = ($instance_dir | path join "disk")
  let output_path = ($output_path | path expand)
  let partial_path = $"($output_path).partial-(random uuid)"

  if not ($disk_path | path exists) {
    error make { msg: $"Instance disk not found: ($disk_path)" }
  }
  if ($output_path | path exists) {
    error make { msg: $"Refusing to overwrite existing image: ($output_path)" }
  }
  if not ($output_path | path dirname | path exists) {
    error make { msg: "Image output directory does not exist." }
  }

  let status = (^limactl list --json $instance_name | from json | get status)
  if $status != "Running" {
    error make { msg: $"Start disposable instance ($instance_name) before export so guest cleanup can be verified." }
  }

  print $"Removing guest data and identity from disposable instance ($instance_name)"
  let cleanup = (open --raw ($env.FILE_PWD | path join "templates" "prepare-base-image.sh"))
  $cleanup | ^limactl shell $instance_name -- sudo sh -s
  if $env.LAST_EXIT_CODE != 0 {
    error make { msg: "Guest cleanup failed; no image was exported." }
  }

  print $"Stopping ($instance_name) before export"
  ^limactl stop $instance_name
  if $env.LAST_EXIT_CODE != 0 {
    error make { msg: "Guest shutdown failed; no image was exported." }
  }
  let stopped_status = (^limactl list --json $instance_name | from json | get status)
  if $stopped_status != "Stopped" {
    error make { msg: $"Guest is ($stopped_status), not Stopped; no image was exported." }
  }

  try {
    ^qemu-img convert -p -O qcow2 $disk_path $partial_path
    if $env.LAST_EXIT_CODE != 0 {
      error make { msg: "Image conversion failed." }
    }
    ^qemu-img check $partial_path
    if $env.LAST_EXIT_CODE != 0 {
      error make { msg: "Exported image failed qemu-img check." }
    }
    mv $partial_path $output_path
  } catch {|err|
    rm -f $partial_path
    error make { msg: $"Export failed: ($err.msg)" }
  }
  print $"Exported ($output_path)"
}
