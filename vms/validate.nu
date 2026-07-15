#!/usr/bin/env nu

use ./lib.nu *

def shell-quote [value: string] {
  "'" + ($value | str replace --all "'" "'\\''") + "'"
}

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

def resolve-guest-user [settings: record] {
  let host_user = (^id -un | str trim)
  get-setting $settings "SCRUBS_GUEST_USER" $host_user
}

def effective-clean-auth-profile [settings: record, explicit_profile: string] {
  if $explicit_profile == "" {
    get-setting $settings "SCRUBS_CLEAN_AUTH_PROFILE" "personal"
  } else {
    $explicit_profile
  }
}

def resolve-github-target [explicit_remote_url: string] {
  let candidate = if $explicit_remote_url != "" {
    $explicit_remote_url | str trim
  } else {
    let remote_result = (do { ^git -C (repo-root) remote get-url origin } | complete)
    if $remote_result.exit_code != 0 {
      error make {
        msg: "Unable to determine the validation GitHub remote from origin."
        help: "Pass --git-remote-url https://github.com/<owner>/<repo>.git to override autodetection."
      }
    }

    $remote_result.stdout | str trim
  }

  let parsed = (
    $candidate
    | parse --regex '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)(?P<owner>[^/]+)/(?P<repo>[^/]+?)(?:\.git)?/?$'
  )

  if ($parsed | is-empty) {
    error make {
      msg: $"Validation Git remote must be a GitHub repository, got: ($candidate)"
      help: "Use --git-remote-url with an https://github.com/<owner>/<repo>.git target."
    }
  }

  let match = ($parsed | first)
  {
    owner: $match.owner
    repo: $match.repo
    https_url: $"https://github.com/($match.owner)/($match.repo).git"
  }
}

def normalize-branch-fragment [value: string] {
  let normalized = (
    $value
    | str lowercase
    | str replace --regex --all '[^a-z0-9]+' "-"
    | str replace --regex '^-+' ""
    | str replace --regex '-+$' ""
  )

  if $normalized == "" {
    "probe"
  } else {
    $normalized
  }
}

def lima-instance-exists [instance_name: string] {
  let list_result = (do { ^limactl list --json } | complete)
  if $list_result.exit_code != 0 {
    error make {
      msg: "Failed to list Lima instances."
      help: (summarize-command-failure $list_result "limactl list --json failed")
    }
  }

  (
    $list_result.stdout
    | lines
    | where {|line| ($line | str trim | str starts-with "{") }
    | each {|line| $line | from json }
    | any {|instance| (($instance.name? | default "") == $instance_name) }
  )
}

def delete-instance [instance_name: string] {
  do { ^limactl delete $instance_name } | complete
}

def stop-instance [instance_name: string] {
  do { ^limactl stop $instance_name } | complete
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

def probe-shell-access [instance_name: string, label: string] {
  let result = (guest-run $instance_name "printf 'shell-ready\n'")
  if $result.exit_code != 0 {
    return (fail-entry $label (summarize-command-failure $result "limactl shell failed"))
  }

  if (($result.stdout | str trim) != "shell-ready") {
    return (fail-entry $label "limactl shell returned an unexpected response")
  }

  pass-entry $label "limactl shell reached the guest cleanly"
}

def probe-sealed-auth-artifacts [instance_name: string] {
  let command = "test -f \"$HOME/.local/share/scrubs/clean-auth/gh-token.enc\" && test -f \"$HOME/.local/share/scrubs/clean-auth/codex-auth.json.enc\" && test -f \"$HOME/.local/share/scrubs/clean-auth/seal-key\""
  let result = (guest-run $instance_name $command)

  if $result.exit_code != 0 {
    return (fail-entry "Sealed clean auth artifacts" "Missing guest-sealed gh or Codex auth material; check host secrets with `just scrubs-auth-status` before rerunning")
  }

  pass-entry "Sealed clean auth artifacts" "Guest bootstrap produced sealed gh and Codex auth artifacts"
}

def probe-gh-auth [instance_name: string, label: string] {
  let result = (guest-run $instance_name "gh auth status --hostname github.com >/dev/null")
  if $result.exit_code != 0 {
    return (fail-entry $label (summarize-command-failure $result "gh auth status failed"))
  }

  pass-entry $label "gh auth status succeeded without interactive login"
}

def probe-codex-login-status [instance_name: string, label: string] {
  let result = (guest-run $instance_name "codex login status >/dev/null")
  if $result.exit_code != 0 {
    return (fail-entry $label (summarize-command-failure $result "codex login status failed"))
  }

  pass-entry $label "Codex login status succeeded without interactive login"
}

def probe-playwright-mcp-config [instance_name: string, label: string] {
  let command = "
test -x /run/current-system/sw/bin/codex-playwright-mcp
codex mcp get playwright | grep -Fq 'command: /run/current-system/sw/bin/codex-playwright-mcp'
grep -Fq 'experimental_environment = \"remote\"' \"$HOME/.codex/config.toml\"
grep -Fq 'required = true' \"$HOME/.codex/config.toml\"
grep -Fq 'default_tools_approval_mode = \"approve\"' \"$HOME/.codex/config.toml\"
"
  let result = (guest-run $instance_name $command)

  if $result.exit_code != 0 {
    return (fail-entry $label (summarize-command-failure $result "Codex Playwright MCP configuration is missing or incomplete"))
  }

  pass-entry $label "Codex has a required, pre-approved remote-STDIO Playwright MCP backed by the scrubs wrapper"
}

def probe-playwright-mcp-tools [instance_name: string, lab_dir: string, label: string] {
  let lab_dir_q = (shell-quote $lab_dir)
  let initialize_q = (shell-quote '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"scrubs-validation","version":"1"}}}')
  let initialized_q = (shell-quote '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}')
  let list_tools_q = (shell-quote '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')
  let command = $"
cd ($lab_dir_q)
printf '%s\n' ($initialize_q) ($initialized_q) ($list_tools_q) | timeout 15 /run/current-system/sw/bin/codex-playwright-mcp --image-responses omit | grep -Fq '"name":"browser_take_screenshot"'
"
  let result = (guest-run $instance_name $command)

  if $result.exit_code != 0 {
    return (fail-entry $label (summarize-command-failure $result "Playwright MCP did not start or expose browser tools"))
  }

  pass-entry $label "Sandboxed Playwright MCP started and exposed browser tools over STDIO"
}

def probe-codex-canonical-home-login-status [instance_name: string, label: string] {
  let command = "
. \"$HOME/.local/libexec/scrubs/clean-auth-lib.sh\"
runtime_auth=\"$(scrubs_runtime_auth_dir)/codex-auth.json\"
rm -f \"$runtime_auth\"
CODEX_HOME=\"$HOME/.codex\" codex login status >/dev/null
test -L \"$HOME/.codex/auth.json\"
test \"$(readlink -f \"$HOME/.codex/auth.json\")\" = \"$runtime_auth\"
test -s \"$runtime_auth\"
"
  let result = (guest-run $instance_name $command)

  if $result.exit_code != 0 {
    return (fail-entry $label (summarize-command-failure $result "Codex login status failed with canonical CODEX_HOME"))
  }

  pass-entry $label "Canonical CODEX_HOME rematerialized sealed ChatGPT auth without interactive login"
}

def probe-codex-marker [instance_name: string, marker_path: string, marker: string] {
  let marker_dir = ($marker_path | path dirname)
  let marker_dir_q = (shell-quote $marker_dir)
  let marker_path_q = (shell-quote $marker_path)
  let marker_q = (shell-quote $marker)
  let prompt_q = (shell-quote $"Reply with exactly ($marker) and nothing else.")
  let command = $"mkdir -p ($marker_dir_q) && codex exec --skip-git-repo-check --output-last-message ($marker_path_q) ($prompt_q) >/dev/null && grep -Fqx ($marker_q) ($marker_path_q)"
  let result = (guest-run $instance_name $command)

  if $result.exit_code != 0 {
    return (fail-entry "Codex continuity marker" (summarize-command-failure $result "Codex could not create the continuity marker"))
  }

  pass-entry "Codex continuity marker" $"Codex wrote a durable marker to ($marker_path)"
}

def prepare-validation-lab [instance_name: string, lab_dir: string] {
  let lab_dir_q = (shell-quote $lab_dir)
  let command = $"
rm -rf ($lab_dir_q)
mkdir -p ($lab_dir_q)
cd ($lab_dir_q)
git init -b main >/dev/null
cat > .mise.toml <<'EOF'
[tools]
just = \"1.52.0\"
EOF
cat > justfile <<'EOF'
probe-dirty-boundary:
    test ! -e \"$HOME/.local/share/scrubs/clean-auth\"
    ! command -v gh >/dev/null 2>&1
    ! command -v codex >/dev/null 2>&1
EOF
printf 'scrubs validation lab\n' > README.md
git config user.name 'Scrubs Validation'
git config user.email 'scrubs-validation@example.invalid'
git add . >/dev/null
git commit -m 'Initialize scrubs validation lab' >/dev/null
"
  let result = (guest-run $instance_name $command)

  if $result.exit_code != 0 {
    return (fail-entry "Validation lab setup" (summarize-command-failure $result "Failed to prepare the guest-local validation lab"))
  }

  pass-entry "Validation lab setup" $"Prepared disposable git + mise fixture at ($lab_dir)"
}

def install-validation-tools [instance_name: string, lab_dir: string] {
  let lab_dir_q = (shell-quote $lab_dir)
  let result = (guest-run $instance_name $"cd ($lab_dir_q) && mise trust .mise.toml >/dev/null && mise install >/dev/null")

  if $result.exit_code != 0 {
    return (fail-entry "Validation lab tool install" (summarize-command-failure $result "mise install failed for the validation lab"))
  }

  pass-entry "Validation lab tool install" "Installed the dirty-space `just` runtime for the guest-local fixture"
}

def probe-dirty-boundary [instance_name: string, lab_dir: string, label: string] {
  let lab_dir_q = (shell-quote $lab_dir)
  let result = (guest-run $instance_name $"cd ($lab_dir_q) && just probe-dirty-boundary >/dev/null")

  if $result.exit_code != 0 {
    return (fail-entry $label (summarize-command-failure $result "Dirty-space probe reached a clean-only path or wrapper"))
  }

  pass-entry $label "Dirty space could not see clean-auth, gh, or codex"
}

def probe-git-credential-fill [instance_name: string, label: string] {
  let command = "printf 'protocol=https\nhost=github.com\n\n' | git credential fill"
  let result = (guest-run $instance_name $command)

  if $result.exit_code != 0 {
    return (fail-entry $label (summarize-command-failure $result "git credential fill failed"))
  }

  let lines = ($result.stdout | lines)
  let username_lines = ($lines | where {|line| $line | str starts-with "username=" })
  let password_lines = ($lines | where {|line| $line | str starts-with "password=" })
  let username = if ($username_lines | is-empty) {
    ""
  } else {
    $username_lines | first | str replace "username=" ""
  }
  let password = if ($password_lines | is-empty) {
    ""
  } else {
    $password_lines | first | str replace "password=" ""
  }

  if $username == "" or $password == "" {
    return (fail-entry $label "git credential fill returned an incomplete GitHub credential response")
  }

  pass-entry $label "git credential fill returned a GitHub username and password through the scrubs helper path"
}

def probe-git-ls-remote [instance_name: string, remote_url: string] {
  let remote_url_q = (shell-quote $remote_url)
  let result = (guest-run $instance_name $"git ls-remote ($remote_url_q) HEAD >/dev/null")

  if $result.exit_code != 0 {
    return (fail-entry "HTTPS Git read probe" (summarize-command-failure $result "git ls-remote failed"))
  }

  pass-entry "HTTPS Git read probe" $"git ls-remote succeeded against ($remote_url)"
}

def probe-git-push-dry-run [instance_name: string, lab_dir: string, remote_url: string, branch_name: string] {
  let lab_dir_q = (shell-quote $lab_dir)
  let remote_url_q = (shell-quote $remote_url)
  let command = $"
cd ($lab_dir_q)
git remote remove validation-origin >/dev/null 2>&1 || true
git remote add validation-origin ($remote_url_q)
git push --dry-run validation-origin HEAD:refs/heads/($branch_name) >/dev/null
"
  let result = (guest-run $instance_name $command)

  if $result.exit_code != 0 {
    return (fail-entry "HTTPS Git push --dry-run probe" (summarize-command-failure $result "git push --dry-run failed"))
  }

  pass-entry "HTTPS Git push --dry-run probe" $"git push --dry-run succeeded against refs/heads/($branch_name)"
}

def probe-codex-marker-survives [instance_name: string, marker_path: string, marker: string] {
  let marker_path_q = (shell-quote $marker_path)
  let marker_q = (shell-quote $marker)
  let result = (guest-run $instance_name $"test -f ($marker_path_q) && grep -Fqx ($marker_q) ($marker_path_q)")

  if $result.exit_code != 0 {
    return (fail-entry "Codex continuity marker survives re-bootstrap" "The Codex marker was missing or changed after re-bootstrap")
  }

  pass-entry "Codex continuity marker survives re-bootstrap" $"Marker at ($marker_path) still matches after re-bootstrap"
}

def print-summary [instance_name: string, results: list<record>] {
  print ""
  print $"Scrubs validation summary for ($instance_name):"
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
  instance_name: string = "scrubs-validate"
  --source-image(-s): string = ""
  --clean-auth-profile(-p): string = ""
  --shim-name: string = ""
  --tailscale-mode: string = "tailscale-disabled"
  --git-remote-url: string = ""
  --skip-git-push-dry-run
  --recreate
] {
  let settings = (load-settings)
  let guest_user = (resolve-guest-user $settings)
  let guest_home = $"/home/($guest_user)"
  let resolved_profile = (effective-clean-auth-profile $settings $clean_auth_profile)
  let resolved_source_image = if $source_image == "" {
    default-base-image $settings
  } else {
    $source_image
  }
  let git_target = (resolve-github-target $git_remote_url)
  let instance_fragment = (normalize-branch-fragment $instance_name)
  let validation_branch = $"scrubs-validation-probe-($instance_fragment)"
  let marker = $"scrubs-validation-marker-($instance_fragment)"
  let marker_path = $"($guest_home)/.codex/scrubs-validation/($instance_fragment)-marker.txt"
  let lab_dir = $"($guest_home)/scrubs-validation-lab"

  if (lima-instance-exists $instance_name) {
    if not $recreate {
      error make {
        msg: $"Lima instance '($instance_name)' already exists."
        help: "Use a disposable guest name or rerun with --recreate for a disposable validation instance."
      }
    }

    print $"Deleting existing disposable instance ($instance_name) before validation..."
    let stop_result = (stop-instance $instance_name)
    if $stop_result.exit_code != 0 {
      error make {
        msg: $"Failed to stop existing Lima instance '($instance_name)' before recreation."
        help: (summarize-command-failure $stop_result "limactl stop failed")
      }
    }
    let delete_result = (delete-instance $instance_name)
    if $delete_result.exit_code != 0 {
      error make {
        msg: $"Failed to delete existing Lima instance '($instance_name)'."
        help: (summarize-command-failure $delete_result "limactl delete failed")
      }
    }
  }

  print $"Scrubs validation target: ($instance_name)"
  print $"Clean auth profile: ($resolved_profile)"
  print $"Base image: ($resolved_source_image)"
  print $"GitHub validation remote: ($git_target.https_url)"
  if $shim_name != "" {
    print $"Project shim: ($shim_name)"
  }
  if $tailscale_mode != "tailscale-disabled" {
    print $"Tailscale bootstrap mode override: ($tailscale_mode)"
  }
  if $skip_git_push_dry_run {
    print "Skipping HTTPS git push --dry-run probe by request."
  }
  print ""

  mut results = []
  mut marker_written = false
  mut lab_ready = false
  mut dirty_runtime_ready = false

  let first_bootstrap = (bootstrap-instance $instance_name $resolved_source_image $resolved_profile $shim_name $tailscale_mode)
  if $first_bootstrap.exit_code != 0 {
    $results = ($results | append (fail-entry "Fresh bootstrap" (summarize-command-failure $first_bootstrap "bootstrap failed")))
    print-summary $instance_name $results
    exit 1
  } else {
    $results = ($results | append (pass-entry "Fresh bootstrap" "Fresh disposable guest bootstrapped successfully"))
  }

  $results = ($results | append (probe-shell-access $instance_name "limactl shell reachability"))
  $results = ($results | append (probe-sealed-auth-artifacts $instance_name))
  $results = ($results | append (probe-codex-canonical-home-login-status $instance_name "Codex SSH-style auth smoke"))
  $results = ($results | append (probe-gh-auth $instance_name "gh auth smoke"))
  $results = ($results | append (probe-codex-login-status $instance_name "Codex auth smoke"))
  $results = ($results | append (probe-playwright-mcp-config $instance_name "Codex Playwright MCP config"))

  let marker_result = (probe-codex-marker $instance_name $marker_path $marker)
  if $marker_result.status == "PASS" {
    $marker_written = true
  }
  $results = ($results | append $marker_result)

  let lab_setup_result = (prepare-validation-lab $instance_name $lab_dir)
  if $lab_setup_result.status == "PASS" {
    $lab_ready = true
  }
  $results = ($results | append $lab_setup_result)

  if $lab_ready {
    $results = ($results | append (probe-playwright-mcp-tools $instance_name $lab_dir "Codex Playwright MCP tools"))
  } else {
    $results = ($results | append (skip-entry "Codex Playwright MCP tools" "Skipped because the guest-local validation lab could not be prepared"))
  }

  if $lab_ready {
    let tool_install_result = (install-validation-tools $instance_name $lab_dir)
    if $tool_install_result.status == "PASS" {
      $dirty_runtime_ready = true
    }
    $results = ($results | append $tool_install_result)
  } else {
    $results = ($results | append (skip-entry "Validation lab tool install" "Skipped because the guest-local validation lab could not be prepared"))
  }

  if $dirty_runtime_ready {
    $results = ($results | append (probe-dirty-boundary $instance_name $lab_dir "Dirty boundary smoke"))
  } else {
    $results = ($results | append (skip-entry "Dirty boundary smoke" "Skipped because the guest-local dirty fixture could not be initialized"))
  }

  $results = ($results | append (probe-git-credential-fill $instance_name "HTTPS Git credential helper smoke"))
  $results = ($results | append (probe-git-ls-remote $instance_name $git_target.https_url))

  if $skip_git_push_dry_run {
    $results = ($results | append (skip-entry "HTTPS Git push --dry-run probe" "Skipped because the validation profile may be read-only"))
  } else if $lab_ready {
    $results = ($results | append (probe-git-push-dry-run $instance_name $lab_dir $git_target.https_url $validation_branch))
  } else {
    $results = ($results | append (skip-entry "HTTPS Git push --dry-run probe" "Skipped because the guest-local validation lab could not be prepared"))
  }

  let second_bootstrap = (bootstrap-instance $instance_name $resolved_source_image $resolved_profile $shim_name $tailscale_mode)
  if $second_bootstrap.exit_code != 0 {
    $results = ($results | append (fail-entry "Repeat bootstrap" (summarize-command-failure $second_bootstrap "repeat bootstrap failed")))
    print-summary $instance_name $results
    exit 1
  } else {
    $results = ($results | append (pass-entry "Repeat bootstrap" "Existing guest survived a second bootstrap run"))
  }

  $results = ($results | append (probe-shell-access $instance_name "limactl shell reachability after re-bootstrap"))
  $results = ($results | append (probe-gh-auth $instance_name "gh auth smoke after re-bootstrap"))
  $results = ($results | append (probe-codex-canonical-home-login-status $instance_name "Codex SSH-style auth smoke after re-bootstrap"))
  $results = ($results | append (probe-codex-login-status $instance_name "Codex auth smoke after re-bootstrap"))
  $results = ($results | append (probe-playwright-mcp-config $instance_name "Codex Playwright MCP config after re-bootstrap"))

  if $lab_ready {
    $results = ($results | append (probe-playwright-mcp-tools $instance_name $lab_dir "Codex Playwright MCP tools after re-bootstrap"))
  } else {
    $results = ($results | append (skip-entry "Codex Playwright MCP tools after re-bootstrap" "Skipped because the guest-local validation lab could not be prepared"))
  }

  if $dirty_runtime_ready {
    $results = ($results | append (probe-dirty-boundary $instance_name $lab_dir "Dirty boundary smoke after re-bootstrap"))
  } else {
    $results = ($results | append (skip-entry "Dirty boundary smoke after re-bootstrap" "Skipped because the guest-local dirty fixture never initialized"))
  }

  $results = ($results | append (probe-git-credential-fill $instance_name "HTTPS Git credential helper smoke after re-bootstrap"))

  if $marker_written {
    $results = ($results | append (probe-codex-marker-survives $instance_name $marker_path $marker))
  } else {
    $results = ($results | append (skip-entry "Codex continuity marker survives re-bootstrap" "Skipped because the initial Codex marker was never written"))
  }

  print-summary $instance_name $results

  let failure_count = ($results | where status == "FAIL" | length)
  if $failure_count > 0 {
    exit 1
  }
}
