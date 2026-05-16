#!/usr/bin/env nu

def main [
  image_name: string = "scrubs-linux-lts.qcow2"
] {
  let repo_root = ($env.FILE_PWD | path dirname | path dirname)
  let local_dir = ($env.SCRUBS_LOCAL_BASE_IMAGE_DIR? | default ($repo_root | path join "scrubs" "qcow2"))
  let icloud_dir = ($env.SCRUBS_ICLOUD_BASE_IMAGE_DIR? | default ($env.HOME | path join "Library" "Mobile Documents" "com~apple~CloudDocs" "scrubs" "base-images"))
  let source_path = ($icloud_dir | path join $image_name)
  let dest_path = ($local_dir | path join $image_name)

  if not ($source_path | path exists) {
    error make { msg: $"iCloud base image not found: ($source_path)" }
  }

  mkdir $local_dir
  cp --force $source_path $dest_path

  print $"Copied ($source_path)"
  print $"to ($dest_path)"
}
