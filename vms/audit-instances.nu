#!/usr/bin/env nu

use ./lib.nu *

def short-rev [rev: string] {
  let trimmed = ($rev | str trim)

  if $trimmed == "" {
    ""
  } else if ($trimmed | str length) <= 7 {
    $trimmed
  } else {
    $trimmed | str substring 0..6
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

def extract-input-ref [flake_nix: string, input_name: string, pattern: string] {
  let match = ($flake_nix | parse --regex $pattern)

  if ($match | is-empty) {
    error make { msg: $"Could not determine the current ($input_name) ref from vms/flake.nix." }
  }

  $match | first | get ref
}

def normalize-release-channel [ref: string] {
  if ($ref | str starts-with "nixos-") {
    $ref | str replace --regex '^nixos-' ""
  } else {
    $ref
  }
}

def format-version-cell [guest_value: string, target_value: string, use_color: bool] {
  if $guest_value == "-" {
    colorize "-" "dark_gray" $use_color
  } else if $guest_value == "" and $target_value == "" {
    colorize "-" "dark_gray" $use_color
  } else if $guest_value == "" {
    colorize $"unknown -> ($target_value)" "cyan_bold" $use_color
  } else if $target_value == "" or $guest_value == $target_value {
    colorize $guest_value "green" $use_color
  } else {
    colorize $"($guest_value) -> ($target_value)" "yellow_bold" $use_color
  }
}

def join-notes [parts: list<string>] {
  if ($parts | is-empty) {
    ""
  } else {
    $parts | str join "; "
  }
}

def load-target [] {
  let vms_root = (vms-dir)
  let flake_nix = (open --raw ($vms_root | path join "flake.nix"))
  let flake_lock = (open --raw ($vms_root | path join "flake.lock") | from json)
  let nixpkgs_ref = (extract-input-ref $flake_nix "nixpkgs" 'nixpkgs\.url = "github:NixOS/nixpkgs/(?P<ref>[^"]+)";')
  let nixpkgs_unstable_ref = (
    extract-input-ref $flake_nix "nixpkgs-unstable" 'nixpkgs-unstable\.url = "github:NixOS/nixpkgs/(?P<ref>[^"]+)";'
  )
  let nixpkgs_revision = ($flake_lock.nodes.nixpkgs.locked.rev | default "")
  let nixpkgs_unstable_revision = ($flake_lock.nodes."nixpkgs-unstable".locked.rev | default "")

  {
    nixos_release: (normalize-release-channel $nixpkgs_ref)
    nixpkgs_ref: $nixpkgs_ref
    nixpkgs_revision: $nixpkgs_revision
    nixpkgs_short_revision: (short-rev $nixpkgs_revision)
    nixpkgs_unstable_ref: $nixpkgs_unstable_ref
    nixpkgs_unstable_revision: $nixpkgs_unstable_revision
    nixpkgs_unstable_short_revision: (short-rev $nixpkgs_unstable_revision)
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

def normalize-guest-version-info [stdout: string] {
  let trimmed = ($stdout | str trim)

  if $trimmed == "" {
    return {
      ok: false
      reason: "empty guest response"
    }
  }

  if ($trimmed | str starts-with "{") {
    let parsed = (try { $trimmed | from json } catch { null })
    if $parsed == null {
      return {
        ok: false
        reason: "guest version response was not valid JSON"
      }
    }

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

def probe-guest-version [instance_name: string] {
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

  normalize-guest-version-info $result.stdout
}

def probe-guest-lock [instance_name: string] {
  let result = (
    do {
      ^limactl shell $instance_name -- sh -lc 'cat "$HOME/scrubs-bootstrap/scrubs/flake.lock" 2>/dev/null'
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
        | default "could not read guest flake.lock"
      )
    }
  }

  let trimmed = ($result.stdout | str trim)
  if $trimmed == "" {
    return {
      ok: false
      reason: 'missing ~/scrubs-bootstrap/scrubs/flake.lock'
    }
  }

  let parsed = (try { $trimmed | from json } catch { null })
  if $parsed == null {
    return {
      ok: false
      reason: "guest flake.lock was not valid JSON"
    }
  }

  {
    ok: true
    nixpkgs_revision: (try { $parsed.nodes.nixpkgs.locked.rev | into string } catch { "" })
    nixpkgs_unstable_revision: (try { $parsed.nodes."nixpkgs-unstable".locked.rev | into string } catch { "" })
  }
}

def probe-instance [instance_name: string] {
  let version_probe = (probe-guest-version $instance_name)
  if not $version_probe.ok {
    return $version_probe
  }

  let lock_probe = (probe-guest-lock $instance_name)
  let running_nixpkgs_revision = ($version_probe.nixpkgs_revision | default "")
  let lock_nixpkgs_revision = if $lock_probe.ok { $lock_probe.nixpkgs_revision | default "" } else { "" }
  let trusted_lock = (
    $lock_probe.ok
    and $lock_nixpkgs_revision != ""
    and (
      $running_nixpkgs_revision == ""
      or $lock_nixpkgs_revision == $running_nixpkgs_revision
    )
  )
  let metadata_notes = (
    [
      (
        if (not $lock_probe.ok) {
          $lock_probe.reason
        } else {
          null
        }
      )
      (
        if (
          $lock_probe.ok
          and $running_nixpkgs_revision != ""
          and $lock_nixpkgs_revision != ""
          and $running_nixpkgs_revision != $lock_nixpkgs_revision
        ) {
          $"guest flake.lock does not match running nixpkgs: (short-rev $lock_nixpkgs_revision) vs (short-rev $running_nixpkgs_revision)"
        } else {
          null
        }
      )
      (
        if $trusted_lock and (($lock_probe.nixpkgs_unstable_revision | default "") == "") {
          "guest flake.lock did not include a nixpkgs-unstable revision"
        } else {
          null
        }
      )
    ]
    | where {|item| $item != null }
    | each {|item| $item | into string }
  )
  let nixpkgs_revision = if $running_nixpkgs_revision != "" {
    $running_nixpkgs_revision
  } else {
    $lock_nixpkgs_revision
  }
  let nixpkgs_unstable_revision = if $trusted_lock {
    $lock_probe.nixpkgs_unstable_revision | default ""
  } else {
    ""
  }

  {
    ok: true
    nixos_version: ($version_probe.nixos_version | default "")
    nixos_release: (extract-version-channel ($version_probe.nixos_version | default ""))
    nixpkgs_revision: $nixpkgs_revision
    nixpkgs_unstable_revision: $nixpkgs_unstable_revision
    metadata_note: (join-notes $metadata_notes)
  }
}

def classify-instance [instance: record, target: record] {
  let state = (maybe-get $instance status "Unknown")
  let name = (maybe-get $instance name "<unnamed>")

  if $state == "Stopped" {
    return {
      instance: $name
      lima_state: $state
      assessment: "stopped"
      nixos_release: "-"
      nixpkgs: "-"
      nixpkgs_unstable: "-"
      note: "not running; cannot assess"
      sort_rank: 4
    }
  }

  let probe = (probe-instance $name)
  if not $probe.ok {
    return {
      instance: $name
      lima_state: $state
      assessment: "unreachable"
      nixos_release: "-"
      nixpkgs: "-"
      nixpkgs_unstable: "-"
      note: $probe.reason
      sort_rank: 3
    }
  }

  let guest_release = ($probe.nixos_release | default "")
  let guest_nixpkgs_revision = ($probe.nixpkgs_revision | default "")
  let guest_nixpkgs_unstable_revision = ($probe.nixpkgs_unstable_revision | default "")
  let guest_nixpkgs_short_revision = (short-rev $guest_nixpkgs_revision)
  let guest_nixpkgs_unstable_short_revision = (short-rev $guest_nixpkgs_unstable_revision)
  let drift_notes = (
    [
      (
        if $guest_release != "" and $guest_release != $target.nixos_release {
          $"nixos release: ($guest_release) -> ($target.nixos_release)"
        } else {
          null
        }
      )
      (
        if (
          $guest_nixpkgs_short_revision != ""
          and $guest_nixpkgs_short_revision != $target.nixpkgs_short_revision
        ) {
          $"nixpkgs: ($guest_nixpkgs_short_revision) -> ($target.nixpkgs_short_revision)"
        } else {
          null
        }
      )
      (
        if (
          $guest_nixpkgs_unstable_short_revision != ""
          and $guest_nixpkgs_unstable_short_revision != $target.nixpkgs_unstable_short_revision
        ) {
          $"nixpkgs-unstable: ($guest_nixpkgs_unstable_short_revision) -> ($target.nixpkgs_unstable_short_revision)"
        } else {
          null
        }
      )
    ]
    | where {|item| $item != null }
    | each {|item| $item | into string }
  )
  let missing_notes = (
    [
      (
        if $guest_release == "" {
          "missing nixos release"
        } else {
          null
        }
      )
      (
        if $guest_nixpkgs_short_revision == "" {
          "missing nixpkgs revision"
        } else {
          null
        }
      )
      (
        if $guest_nixpkgs_unstable_short_revision == "" {
          "missing nixpkgs-unstable revision"
        } else {
          null
        }
      )
    ]
    | where {|item| $item != null }
    | each {|item| $item | into string }
  )
  let note_parts = (
    [
      (
        if not ($drift_notes | is-empty) {
          join-notes $drift_notes
        } else {
          null
        }
      )
      (
        if (
          ($drift_notes | is-empty)
          and not ($missing_notes | is-empty)
        ) {
          join-notes $missing_notes
        } else {
          null
        }
      )
      (
        if ($probe.metadata_note | default "") != "" {
          $probe.metadata_note
        } else {
          null
        }
      )
    ]
    | where {|item| $item != null }
    | each {|item| $item | into string }
  )
  let assessment = if not ($drift_notes | is-empty) {
    "stale"
  } else if not ($missing_notes | is-empty) {
    "unknown"
  } else {
    "current"
  }
  let sort_rank = match $assessment {
    "stale" => 0
    "unknown" => 1
    "current" => 2
    _ => 2
  }

  {
    instance: $name
    lima_state: $state
    assessment: $assessment
    nixos_release: $guest_release
    nixpkgs: $guest_nixpkgs_short_revision
    nixpkgs_unstable: $guest_nixpkgs_unstable_short_revision
    note: (
      if ($note_parts | is-empty) {
        "up to date"
      } else {
        join-notes $note_parts
      }
    )
    sort_rank: $sort_rank
  }
}

def style-assessment [assessment: string, use_color: bool] {
  match $assessment {
    "current" => (colorize "CURRENT" "green_bold" $use_color)
    "stale" => (colorize "STALE" "yellow_bold" $use_color)
    "unknown" => (colorize "UNKNOWN" "cyan_bold" $use_color)
    "unreachable" => (colorize "UNREACHABLE" "red_bold" $use_color)
    "stopped" => (colorize "STOPPED" "dark_gray" $use_color)
    _ => (colorize ($assessment | str uppercase) "light_gray" $use_color)
  }
}

def render-table [rows: table, target: record, use_color: bool] {
  $rows
  | sort-by sort_rank instance
  | each {|row|
      {
        status: (style-assessment $row.assessment $use_color)
        instance: $row.instance
        lima: $row.lima_state
        nixos_release: (format-version-cell $row.nixos_release $target.nixos_release $use_color)
        nixpkgs: (format-version-cell $row.nixpkgs $target.nixpkgs_short_revision $use_color)
        nixpkgs_unstable: (format-version-cell $row.nixpkgs_unstable $target.nixpkgs_unstable_short_revision $use_color)
        note: $row.note
      }
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
  render-table $rows $target $use_color
}
