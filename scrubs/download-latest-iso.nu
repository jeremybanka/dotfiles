#!/usr/bin/env nu

def main [
  channel: string = "nixos-25.11"
] {
  let arch = ($env.SCRUBS_SEED_ARCH? | default "aarch64")
  let flavor = ($env.SCRUBS_SEED_FLAVOR? | default "minimal")
  let cache_dir = ($env.SCRUBS_ISO_CACHE_DIR? | default ($env.HOME | path join "Library" "Caches" "scrubs"))

  if $arch not-in ["aarch64", "x86_64"] {
    error make { msg: $"Unsupported architecture: ($arch). Use aarch64 or x86_64." }
  }

  if $flavor not-in ["minimal", "graphical"] {
    error make { msg: $"Unsupported ISO flavor: ($flavor). Use minimal or graphical." }
  }

  mkdir $cache_dir

  let latest_url = $"https://channels.nixos.org/($channel)/latest-nixos-($flavor)-($arch)-linux.iso"
  let file_name = ($env.SCRUBS_SEED_ISO_FILE? | default $"nixos-($flavor)-($arch).iso")
  let output_path = ($cache_dir | path join $file_name)
  let resolved_url_file = $"($output_path).source-url"
  let sha256_file = $"($output_path).sha256"

  print $"Downloading ($latest_url)"
  ^curl --fail --location --continue-at - --output $output_path $latest_url

  let resolved_url = (^curl --silent --show-error --location --output /dev/null --write-out "%{url_effective}" $latest_url | str trim)
  $resolved_url | save --force $resolved_url_file

  let sha256 = (^shasum -a 256 $output_path | split row " " | get 0)
  $"($sha256)  ($file_name)\n" | save --force $sha256_file

  print $"Saved ISO to ($output_path)"
  print $"Resolved release URL: ($resolved_url)"
  print $"Local SHA-256: ($sha256)"
  print "Metadata:"
  print $"  ($resolved_url_file)"
  print $"  ($sha256_file)"
}
