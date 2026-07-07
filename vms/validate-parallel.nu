#!/usr/bin/env nu

use ./lib.nu *

def pass-entry [name: string, detail: string] {
  {
    status: "PASS"
    name: $name
    detail: $detail
  }
}

def fail-entry [name: string, detail: string] {
  {
    status: "FAIL"
    name: $name
    detail: $detail
  }
}

def skip-entry [name: string, detail: string] {
  {
    status: "SKIP"
    name: $name
    detail: $detail
  }
}

def summarize-command-failure [result: record, fallback: string] {
  let stderr = ($result.stderr | str trim)
  if $stderr != "" {
    $stderr | lines | last
  } else {
    let stdout = ($result.stdout | str trim)
    if $stdout != "" {
      $stdout | lines | last
    } else {
      $fallback
    }
  }
}

def default-base-image [settings: record] {
  let configured = (get-setting $settings "SCRUBS_BASE_IMAGE" "")
  if $configured == "" {
    vms-dir | path join "images" "scrubs.qcow2"
  } else {
    expand-home $configured
  }
}

def effective-clean-auth-profile [settings: record, explicit_profile: string] {
  if $explicit_profile == "" {
    get-setting $settings "SCRUBS_CLEAN_AUTH_PROFILE" "personal"
  } else {
    $explicit_profile
  }
}

def representative-batch [batch_prefix: string] {
  [
    {
      instance_name: $"($batch_prefix)-base"
      shim_name: ""
      label: "base"
    }
    {
      instance_name: $"($batch_prefix)-moview"
      shim_name: "moview"
      label: "moview shim"
    }
    {
      instance_name: $"($batch_prefix)-systemd-ts"
      shim_name: "systemd-ts"
      label: "systemd-ts shim"
    }
  ]
}

def display-spec [spec: record] {
  if ($spec.shim_name | default "") == "" {
    $spec.instance_name
  } else {
    $"($spec.instance_name) [shim: ($spec.shim_name)]"
  }
}

def load-instance-info [instance_name: string] {
  let result = (do { ^limactl list --json $instance_name } | complete)
  if $result.exit_code != 0 {
    return {}
  }

  try {
    $result.stdout | from json
  } catch {
    {}
  }
}

def instance-status [instance_info: record] {
  $instance_info | get -o status | default "" | into string
}

def instance-ssh-port [instance_info: record] {
  $instance_info | get -o sshLocalPort | default "" | into string
}

def lima-instance-exists [instance_name: string] {
  not ((load-instance-info $instance_name | columns) | is-empty)
}

def stop-instance [instance_name: string] {
  do { ^limactl stop $instance_name } | complete
}

def delete-instance [instance_name: string] {
  do { ^limactl delete $instance_name } | complete
}

def bootstrap-instance [
  instance_name: string
  source_image: string
  clean_auth_profile: string
  shim_name: string
  tailscale_mode: string
] {
  let script_path = (vms-dir | path join "bootstrap.nu")
  mut args = [$script_path]

  if $source_image != "" {
    $args = ($args | append "--source-image")
    $args = ($args | append $source_image)
  }

  if $shim_name != "" {
    $args = ($args | append "--shim-name")
    $args = ($args | append $shim_name)
  }

  if $clean_auth_profile != "" {
    $args = ($args | append "--clean-auth-profile")
    $args = ($args | append $clean_auth_profile)
  }

  $args = ($args | append $instance_name)
  $args = ($args | append $tailscale_mode)

  let call_args = $args
  do { ^nu ...$call_args } | complete
}

def guest-run [instance_name: string, command: string] {
  do { ^limactl shell $instance_name -- sh -lc $command } | complete
}

def prepare-batch [batch: list<record>, recreate: bool] {
  for spec in $batch {
    if not (lima-instance-exists $spec.instance_name) {
      continue
    }

    if not $recreate {
      error make {
        msg: $"Lima instance '($spec.instance_name)' already exists."
        help: "Use a disposable validation prefix or rerun with --recreate for the disposable batch."
      }
    }

    print $"Deleting existing disposable instance ($spec.instance_name) before parallel validation..."
    let instance_status = (instance-status (load-instance-info $spec.instance_name))
    if $instance_status != "" and $instance_status != "Stopped" {
      let stop_result = (stop-instance $spec.instance_name)
      if $stop_result.exit_code != 0 {
        error make {
          msg: $"Failed to stop existing Lima instance '($spec.instance_name)' before recreation."
          help: (summarize-command-failure $stop_result "limactl stop failed")
        }
      }
    }

    let delete_result = (delete-instance $spec.instance_name)
    if $delete_result.exit_code != 0 {
      error make {
        msg: $"Failed to delete existing Lima instance '($spec.instance_name)'."
        help: (summarize-command-failure $delete_result "limactl delete failed")
      }
    }
  }
}

def check-distinct-ssh-listeners [batch: list<record>] {
  let listeners = (
    $batch
    | each {|spec|
        let instance_info = (load-instance-info $spec.instance_name)
        {
          instance_name: $spec.instance_name
          status: (instance-status $instance_info)
          ssh_port: (instance-ssh-port $instance_info)
        }
      }
    | sort-by instance_name
  )

  let missing_ports = ($listeners | where {|listener| $listener.ssh_port == "" })
  if not ($missing_ports | is-empty) {
    let detail = (
      $missing_ports
      | each {|listener| $"($listener.instance_name) status=($listener.status | default 'unknown')" }
      | str join ", "
    )
    return (fail-entry "Distinct SSH listeners" $"Missing sshLocalPort for: ($detail)")
  }

  let non_running = ($listeners | where {|listener| $listener.status != "Running" })
  if not ($non_running | is-empty) {
    let detail = (
      $non_running
      | each {|listener| $"($listener.instance_name)=($listener.status)" }
      | str join ", "
    )
    return (fail-entry "Distinct SSH listeners" $"Expected Running status after bootstrap, saw: ($detail)")
  }

  let duplicate_ports = (
    $listeners
    | group-by ssh_port
    | transpose ssh_port entries
    | where {|row| ($row.entries | length) > 1 }
    | each {|row|
        {
          ssh_port: $row.ssh_port
          names: ($row.entries | get instance_name | sort)
        }
      }
  )

  if not ($duplicate_ports | is-empty) {
    let detail = (
      $duplicate_ports
      | each {|row| $"port ($row.ssh_port): (($row.names | str join ', '))" }
      | str join "; "
    )
    return (fail-entry "Distinct SSH listeners" $"Duplicate host SSH listeners detected: ($detail)")
  }

  let detail = (
    $listeners
    | each {|listener| $"($listener.instance_name)=($listener.ssh_port)" }
    | str join ", "
  )
  pass-entry "Distinct SSH listeners" $"Validated unique host SSH listeners: ($detail)"
}

def probe-shell-access [batch: list<record>] {
  let failures = (
    $batch
    | each {|spec|
        let result = (guest-run $spec.instance_name "printf 'parallel-shell-ready\n'")
        if $result.exit_code != 0 {
          {
            instance_name: $spec.instance_name
            detail: (summarize-command-failure $result "limactl shell failed")
          }
        } else if (($result.stdout | str trim) != "parallel-shell-ready") {
          {
            instance_name: $spec.instance_name
            detail: "limactl shell returned an unexpected response"
          }
        } else {
          null
        }
      }
    | where {|entry| $entry != null }
  )

  if not ($failures | is-empty) {
    let detail = (
      $failures
      | each {|failure| $"($failure.instance_name): ($failure.detail)" }
      | str join "; "
    )
    return (fail-entry "limactl shell reachability" $detail)
  }

  pass-entry "limactl shell reachability" "limactl shell reached every guest in the parallel batch"
}

def probe-audit-health [batch: list<record>] {
  let audit_script = (vms-dir | path join "audit-instances.nu")
  let call_args = ([$audit_script "--json"] | append ($batch | get instance_name))
  let result = (do { ^nu ...$call_args } | complete)

  if $result.exit_code != 0 {
    return (fail-entry "Unsandboxed audit health" (summarize-command-failure $result "audit-instances failed"))
  }

  let parsed = (try { $result.stdout | from json } catch { null })
  if $parsed == null {
    return (fail-entry "Unsandboxed audit health" "audit-instances --json did not produce valid JSON")
  }

  let non_current = ($parsed | where {|row| $row.assessment != "current" })
  if not ($non_current | is-empty) {
    let detail = (
      $non_current
      | each {|row| $"($row.instance)=($row.assessment)" }
      | str join ", "
    )
    return (fail-entry "Unsandboxed audit health" $"Expected CURRENT audit status for the validation batch, saw: ($detail)")
  }

  pass-entry "Unsandboxed audit health" "audit-instances reported CURRENT for the validation batch"
}

def print-summary [batch_prefix: string, results: list<record>] {
  print ""
  print $"Parallel scrubs validation summary for ($batch_prefix):"
  for entry in $results {
    print $"[($entry.status)] ($entry.name): ($entry.detail)"
  }

  let pass_count = ($results | where status == "PASS" | length)
  let fail_count = ($results | where status == "FAIL" | length)
  let skip_count = ($results | where status == "SKIP" | length)
  print ""
  print $"Passed: ($pass_count)  Failed: ($fail_count)  Skipped: ($skip_count)"
}

def main [
  batch_prefix: string = "scrubs-validate-parallel"
  --source-image(-s): string = ""
  --clean-auth-profile(-p): string = ""
  --tailscale-mode: string = "tailscale-disabled"
  --skip-audit
  --recreate
] {
  let settings = (load-settings)
  let resolved_profile = (effective-clean-auth-profile $settings $clean_auth_profile)
  let resolved_source_image = if $source_image == "" {
    default-base-image $settings
  } else {
    $source_image
  }
  let batch = (representative-batch $batch_prefix)

  prepare-batch $batch $recreate

  print $"Parallel scrubs validation prefix: ($batch_prefix)"
  print $"Clean auth profile: ($resolved_profile)"
  print $"Base image: ($resolved_source_image)"
  print $"Tailscale bootstrap mode: ($tailscale_mode)"
  print "Representative batch:"
  for spec in ($batch | sort-by instance_name) {
    print $"  - (display-spec $spec)"
  }
  if $skip_audit {
    print "Skipping audit-instances by request."
  } else {
    print "Audit note: run this on the host, not inside a restricted sandbox, so audit-instances can assess the guests accurately."
  }
  print ""
  print "Bootstrapping the representative batch in parallel..."

  mut results = []
  let bootstrap_results = (
    $batch
    | par-each {|spec|
        let bootstrap_result = (bootstrap-instance $spec.instance_name $resolved_source_image $resolved_profile $spec.shim_name $tailscale_mode)
        {
          instance_name: $spec.instance_name
          shim_name: $spec.shim_name
          exit_code: $bootstrap_result.exit_code
          detail: (summarize-command-failure $bootstrap_result "bootstrap failed")
        }
      }
    | sort-by instance_name
  )

  let bootstrap_failures = ($bootstrap_results | where {|result| $result.exit_code != 0 })
  if not ($bootstrap_failures | is-empty) {
    let detail = (
      $bootstrap_failures
      | each {|failure|
          let shim_fragment = if $failure.shim_name == "" {
            ""
          } else {
            $" [shim: ($failure.shim_name)]"
          }
          $"($failure.instance_name)($shim_fragment): ($failure.detail)"
        }
      | str join "; "
    )
    $results = ($results | append (fail-entry "Parallel bootstrap batch" $detail))
    print-summary $batch_prefix $results
    exit 1
  }

  let bootstrapped_detail = (
    $bootstrap_results
    | each {|result|
        if $result.shim_name == "" {
          $result.instance_name
        } else {
          $"($result.instance_name) [shim: ($result.shim_name)]"
        }
      }
    | str join ", "
  )
  $results = ($results | append (pass-entry "Parallel bootstrap batch" $"Bootstrapped in parallel: ($bootstrapped_detail)"))
  $results = ($results | append (check-distinct-ssh-listeners $batch))
  $results = ($results | append (probe-shell-access $batch))

  if $skip_audit {
    $results = ($results | append (skip-entry "Unsandboxed audit health" "Skipped by request; this check normally confirms CURRENT status across the representative batch"))
  } else {
    $results = ($results | append (probe-audit-health $batch))
  }

  print-summary $batch_prefix $results

  let failure_count = ($results | where status == "FAIL" | length)
  if $failure_count > 0 {
    exit 1
  }
}
