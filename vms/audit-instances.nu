#!/usr/bin/env nu

use ./lib.nu *

def short-rev [rev: string] {
  if ($rev | str length) <= 7 {
    $rev
  } else {
    $rev | str substring 0..6
  }
}

def extract-version-channel [version: string] {
  let parsed = ($version | parse --regex '^(?P<channel>\d+\.\d+)')
  if ($parsed | is-empty) {
    ""
  } else {
    $parsed | first | get channel
  }
}

def colorize [text: string, color: string, use_color: bool] {
  if not $use_color {
    $text
  } else {
    $"(ansi $color)($text)(ansi reset)"
  }
}

def plain-width [value: any] {
  $value | into string | ansi strip | str length
}

def pad-right [text: string, width: int] {
  let visible = (plain-width $text)
  let padding = if $width > $visible { $width - $visible } else { 0 }
  $text + (" " | fill --character " " --width $padding)
}

def extract-target-channel [flake_nix: string] {
  let match = (
    $flake_nix
    | parse --regex 'nixpkgs\.url = "github:NixOS/nixpkgs/(?P<ref>[^"]+)";'
  )

  if ($match | is-empty) {
    error make { msg: "Could not determine the current nixpkgs ref from vms/flake.nix." }
  }

  let ref = ($match | first | get ref)
  let channel = if ($ref | str starts-with "nixos-") {
    $ref | str replace --regex '^nixos-' ""
  } else {
    $ref
  }

  {
    ref: $ref
    channel: $channel
  }
}

def load-target [] {
  let vms_root = (vms-dir)
  let flake_nix = (open --raw ($vms_root | path join "flake.nix"))
  let flake_lock = (open --raw ($vms_root | path join "flake.lock") | from json)
  let channel_info = (extract-target-channel $flake_nix)
  let rev = ($flake_lock.nodes.nixpkgs.locked.rev | default "")

  {
    ref: $channel_info.ref
    channel: $channel_info.channel
    rev: $rev
    short_rev: (short-rev $rev)
    label: $"($channel_info.channel) @ (short-rev $rev)"
  }
}

def load-instances [] {
  let result = (do { ^limactl list --json } | complete)
  if $result.exit_code != 0 {
    error make {
      msg: "Failed to list Lima instances."
      label: {
        text: ($result.stderr | str trim)
      }
    }
  }

  $result.stdout
  | lines
  | where {|line| ($line | str trim | str starts-with "{") }
  | each {|line| $line | from json }
  | sort-by name
}

def maybe-get [record: any, path: cell-path, fallback: any = ""] {
  try {
    $record | get $path
  } catch {
    $fallback
  }
}

def normalize-guest-info [stdout: string] {
  let trimmed = ($stdout | str trim)

  if $trimmed == "" {
    return {
      ok: false
      reason: "empty guest response"
    }
  }

  if ($trimmed | str starts-with "{") {
    let parsed = ($trimmed | from json)
    let nixos_version = (
      (maybe-get $parsed nixosVersion "")
      | default (maybe-get $parsed nixos-version "")
      | default (maybe-get $parsed version "")
    )
    let nixpkgs_revision = (
      (maybe-get $parsed nixpkgsRevision "")
      | default (maybe-get $parsed nixpkgs-revision "")
      | default ""
    )
    let configuration_revision = (
      (maybe-get $parsed configurationRevision "")
      | default (maybe-get $parsed configuration-revision "")
      | default ""
    )

    return {
      ok: true
      nixos_version: ($nixos_version | into string)
      nixpkgs_revision: ($nixpkgs_revision | into string)
      configuration_revision: ($configuration_revision | into string)
    }
  }

  {
    ok: true
    nixos_version: $trimmed
    nixpkgs_revision: ""
    configuration_revision: ""
  }
}

def probe-instance [instance_name: string] {
  let result = (
    do {
      ^limactl shell $instance_name -- sh -lc "nixos-version --json 2>/dev/null || nixos-version"
    } | complete
  )

  if $result.exit_code != 0 {
    return {
      ok: false
      reason: (
        $result.stderr
        | str trim
        | lines
        | last
        | default $"guest probe failed with exit code ($result.exit_code)"
      )
    }
  }

  normalize-guest-info $result.stdout
}

def classify-instance [instance: record, target: record] {
  let state = (maybe-get $instance status "Unknown")
  let name = (maybe-get $instance name "<unnamed>")

  if $state == "Stopped" {
    return {
      instance: $name
      lima_state: $state
      assessment: "stopped"
      target: $target.label
      guest: "-"
      note: "not running; cannot assess"
      sort_rank: 3
    }
  }

  let probe = (probe-instance $name)
  if not $probe.ok {
    return {
      instance: $name
      lima_state: $state
      assessment: "unreachable"
      target: $target.label
      guest: "unknown"
      note: $probe.reason
      sort_rank: 2
    }
  }

  let guest_version = ($probe.nixos_version | default "unknown")
  let guest_channel = (extract-version-channel $guest_version)
  let guest_rev = ($probe.nixpkgs_revision | default "")
  let guest_short_rev = if $guest_rev == "" { "" } else { short-rev $guest_rev }
  let guest_label = if $guest_short_rev == "" {
    $guest_version
  } else {
    $"($guest_version) @ ($guest_short_rev)"
  }

  if $guest_channel != "" and $guest_channel != $target.channel {
    return {
      instance: $name
      lima_state: $state
      assessment: "stale"
      target: $target.label
      guest: $guest_label
      note: $"branch drift: ($guest_channel) -> ($target.channel)"
      sort_rank: 1
    }
  }

  if $guest_channel == $target.channel and $guest_rev != "" and $guest_rev != $target.rev {
    return {
      instance: $name
      lima_state: $state
      assessment: "current"
      target: $target.label
      guest: $guest_label
      note: $"on target release line; revision differs: ($guest_short_rev) vs ($target.short_rev)"
      sort_rank: 0
    }
  }

  if $guest_channel == $target.channel or ($guest_rev != "" and $guest_rev == $target.rev) {
    return {
      instance: $name
      lima_state: $state
      assessment: "current"
      target: $target.label
      guest: $guest_label
      note: "up to date"
      sort_rank: 0
    }
  }

  {
    instance: $name
    lima_state: $state
    assessment: "stale"
    target: $target.label
    guest: $guest_label
    note: $"branch drift: ($guest_version) -> ($target.channel)"
    sort_rank: 1
  }
}

def style-assessment [assessment: string, use_color: bool] {
  match $assessment {
    "current" => (colorize "CURRENT" "green_bold" $use_color)
    "stale" => (colorize "STALE" "yellow_bold" $use_color)
    "unreachable" => (colorize "UNREACHABLE" "red_bold" $use_color)
    "stopped" => (colorize "STOPPED" "dark_gray" $use_color)
    _ => (colorize ($assessment | str upcase) "light_gray" $use_color)
  }
}

def render-summary [rows: table, target: record, use_color: bool] {
  let current_count = ($rows | where assessment == "current" | length)
  let stale_count = ($rows | where assessment == "stale" | length)
  let unreachable_count = ($rows | where assessment == "unreachable" | length)
  let stopped_count = ($rows | where assessment == "stopped" | length)
  let total = ($rows | length)
  let target_label = (colorize $target.label "cyan_bold" $use_color)
  let current_label = (colorize ($current_count | into string) "green_bold" $use_color)
  let stale_label = (colorize ($stale_count | into string) "yellow_bold" $use_color)
  let unreachable_label = (colorize ($unreachable_count | into string) "red_bold" $use_color)
  let stopped_label = (colorize ($stopped_count | into string) "dark_gray" $use_color)

  print $"scrubs target: ($target_label)"
  print $"instances: ($total)  current: ($current_label)  stale: ($stale_label)  unreachable: ($unreachable_label)  stopped: ($stopped_label)"
  print ""
}

def render-table [rows: table, use_color: bool] {
  let display_rows = (
    $rows
    | sort-by sort_rank instance
    | each {|row|
        {
          status: (style-assessment $row.assessment $use_color)
          instance: $row.instance
          lima: $row.lima_state
          guest: $row.guest
          target: $row.target
          note: $row.note
        }
      }
  )

  let columns = [
    { key: "status", header: "STATUS" }
    { key: "instance", header: "INSTANCE" }
    { key: "lima", header: "LIMA" }
    { key: "guest", header: "GUEST NIXOS" }
    { key: "target", header: "TARGET" }
    { key: "note", header: "NOTE" }
  ]

  let widths = (
    $columns
    | each {|column|
        let cell_width = (
          $display_rows
          | each {|row| plain-width ($row | get $column.key) }
          | append (plain-width $column.header)
          | math max
        )
        { key: $column.key, width: $cell_width }
      }
  )

  let header = (
    $columns
    | each {|column|
        let width = ($widths | where key == $column.key | first | get width)
        pad-right $column.header $width
      }
    | str join "  "
  )

  print (colorize $header "blue_bold" $use_color)

  for row in $display_rows {
    let rendered = (
      $columns
      | each {|column|
          let width = ($widths | where key == $column.key | first | get width)
          pad-right ($row | get $column.key | into string) $width
        }
      | str join "  "
    )
    print $rendered
  }
}

def main [
  --no-color
] {
  let use_color = (not $no_color)
  let target = (load-target)
  let instances = (load-instances)

  if ($instances | is-empty) {
    print "No Lima instances found."
    return
  }

  let rows = ($instances | each {|instance| classify-instance $instance $target })
  render-summary $rows $target $use_color
  render-table $rows $use_color
}
