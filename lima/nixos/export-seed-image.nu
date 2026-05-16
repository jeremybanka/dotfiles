#!/usr/bin/env nu

def main [
  instance_name: string
  output_path: string
] {
  let instance_dir = ($env.HOME | path join ".lima" $instance_name)
  let disk_path = ($instance_dir | path join "disk")
  let output_path = ($output_path | path expand)

  if not ($disk_path | path exists) {
    error make { msg: $"Instance disk not found: ($disk_path)" }
  }

  print $"Stopping Lima instance ($instance_name) if it is still running"
  do { ^limactl stop $instance_name } | complete | ignore

  print $"Exporting base image to ($output_path)"
  ^qemu-img convert -p -O qcow2 $disk_path $output_path

  print "Done."
}
