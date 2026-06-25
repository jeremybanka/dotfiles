#!/usr/bin/env nu

def timestamp [] {
  date now | format date "%Y-%m-%dT%H:%M:%S%z"
}

def log [level: string, message: string] {
  print $"(timestamp) [($level)] ($message)"
}

def print-stream [stream_name: string, text: string] {
  let trimmed = ($text | str trim)
  if $trimmed == "" {
    return
  }

  for line in ($trimmed | lines) {
    log $stream_name $line
  }
}

def run-command [
  label: string
  command: closure
  --allow-failure
] {
  log INFO $label
  let result = (do $command | complete)
  print-stream STDOUT $result.stdout
  print-stream STDERR $result.stderr

  if $result.exit_code == 0 {
    log INFO $"Completed: ($label)"
  } else {
    let message = $"Command failed with exit code ($result.exit_code): ($label)"
    if $allow_failure {
      log WARN $message
    } else {
      error make { msg: $message }
    }
  }

  $result
}

def build-guest-script [dry_run: bool] {
  let dry_flag = if $dry_run { "1" } else { "0" }
  [
    $"FREE_DRY_RUN=\"($dry_flag)\""
    ''
    'log() {'
    '  level="$1"'
    '  shift'
    '  printf "%s [%s] %s\n" "$(date -Iseconds)" "$level" "$*"'
    '}'
    ''
    'have() {'
    '  command -v "$1" >/dev/null 2>&1'
    '}'
    ''
    'size_of() {'
    '  target="$1"'
    '  if [ -e "$target" ]; then'
    '    du -sh "$target" 2>/dev/null | awk "NR == 1 { print \$1 }"'
    '  else'
    '    printf "0B\n"'
    '  fi'
    '}'
    ''
    'sudo_ready() {'
    '  sudo -n true >/dev/null 2>&1'
    '}'
    ''
    'remove_path() {'
    '  target="$1"'
    '  label="$2"'
    ''
    '  if [ ! -e "$target" ]; then'
    '    log INFO "$label missing at $target; skipping"'
    '    return 0'
    '  fi'
    ''
    '  size="$(size_of "$target")"'
    '  log INFO "$label at $target currently uses $size"'
    ''
    '  if [ "$FREE_DRY_RUN" = "1" ]; then'
    '    log INFO "dry-run: would remove $target"'
    '    return 0'
    '  fi'
    ''
    '  rm -rf -- "$target"'
    '  log INFO "Removed $label at $target"'
    '}'
    ''
    'remove_children() {'
    '  target="$1"'
    '  label="$2"'
    ''
    '  if [ ! -d "$target" ]; then'
    '    log INFO "$label missing at $target; skipping"'
    '    return 0'
    '  fi'
    ''
    '  size="$(size_of "$target")"'
    '  count="$(find "$target" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | awk "{ print \$1 }")"'
    '  log INFO "$label at $target currently uses $size across $count entries"'
    ''
    '  if [ "$count" = "0" ]; then'
    '    log INFO "$label is already empty"'
    '    return 0'
    '  fi'
    ''
    '  if [ "$FREE_DRY_RUN" = "1" ]; then'
    '    log INFO "dry-run: would remove children under $target"'
    '    return 0'
    '  fi'
    ''
    '  find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +'
    '  log INFO "Removed children under $target"'
    '}'
    ''
    'log INFO "Starting guest cleanup"'
    'log INFO "Dry-run mode: $FREE_DRY_RUN"'
    'log INFO "Guest disk usage before cleanup:"'
    'df -h /'
    ''
    'runtime_cache_root="/tmp/scrubs-dirty-runtime-cache/$USER"'
    'if ps -ef | grep -E "[s]crubs-dirty|[b]wrap" >/dev/null 2>&1; then'
    '  log WARN "Detected active scrubs dirty-space processes; leaving $runtime_cache_root intact"'
    'else'
    '  remove_children "$runtime_cache_root" "scrubs dirty runtime cache"'
    'fi'
    ''
    'for temp_path in \'
    '  /tmp/aube-eval \'
    '  /tmp/aube-cache \'
    '  /tmp/node-compile-cache \'
    '  /tmp/dprint-cache \'
    '  /tmp/mise-cache'
    'do'
    '  if ps -ef | grep -F "$temp_path" | grep -v grep >/dev/null 2>&1; then'
    '    log WARN "Detected active process referencing $temp_path; skipping"'
    '  else'
    '    remove_path "$temp_path" "temporary cache"'
    '  fi'
    'done'
    ''
    'vscode_servers_dir="$HOME/.vscode-server/cli/servers"'
    'if [ -d "$vscode_servers_dir" ]; then'
    '  active_ids="$(ps -ef | sed -n "s#.*\\.vscode-server/cli/servers/\\([^/]*\\)/.*#\\1#p" | sort -u)"'
    '  removed_any=0'
    ''
    '  for server_dir in "$vscode_servers_dir"/*; do'
    '    if [ ! -e "$server_dir" ]; then'
    '      continue'
    '    fi'
    ''
    '    server_name="$(basename "$server_dir")"'
    '    if printf "%s\n" "$active_ids" | grep -Fx "$server_name" >/dev/null 2>&1; then'
    '      log INFO "Keeping active VS Code server $server_name"'
    '      continue'
    '    fi'
    ''
    '    removed_any=1'
    '    remove_path "$server_dir" "inactive VS Code server"'
    '  done'
    ''
    '  if [ "$removed_any" = "0" ]; then'
    '    log INFO "No inactive VS Code server directories found"'
    '  fi'
    'else'
    '  log INFO "VS Code server cache not present; skipping"'
    'fi'
    ''
    'if have mise; then'
    '  log INFO "Found mise; pruning unused tool versions"'
    '  if [ "$FREE_DRY_RUN" = "1" ]; then'
    '    mise prune --dry-run --tools'
    '  else'
    '    mise prune --yes --tools'
    '  fi'
    'else'
    '  log INFO "mise not found; skipping mise prune"'
    'fi'
    ''
    'if have pnpm; then'
    '  log INFO "Found pnpm; scanning for local pnpm stores"'
    '  local_store_dirs="$(find "$HOME" -maxdepth 4 -type d -name .pnpm-store 2>/dev/null | sort)"'
    ''
    '  if [ -z "$local_store_dirs" ]; then'
    '    log INFO "No local .pnpm-store directories found"'
    '  else'
    '    printf "%s\n" "$local_store_dirs" | while IFS= read -r store_dir; do'
    '      [ -n "$store_dir" ] || continue'
    '      project_dir="$(dirname "$store_dir")"'
    '      size="$(size_of "$store_dir")"'
    ''
    '      if [ ! -f "$project_dir/package.json" ]; then'
    '        log WARN "Skipping $store_dir because $project_dir does not look like a package root"'
    '        continue'
    '      fi'
    ''
    '      log INFO "Pruning pnpm store for $project_dir ($size)"'
    '      if [ "$FREE_DRY_RUN" = "1" ]; then'
    '        log INFO "dry-run: would change into $project_dir and run pnpm store prune"'
    '      else'
    '        ('
    '          cd "$project_dir"'
    '          pnpm store prune'
    '        )'
    '      fi'
    '    done'
    '  fi'
    'else'
    '  log INFO "pnpm not found; skipping pnpm cleanup"'
    'fi'
    ''
    'if have nix-collect-garbage; then'
    '  if sudo_ready; then'
    '    log INFO "Running Nix garbage collection"'
    '    if [ "$FREE_DRY_RUN" = "1" ]; then'
    '      sudo -n nix-collect-garbage -d --dry-run'
    '    else'
    '      sudo -n nix-collect-garbage -d'
    '    fi'
    '  else'
    '    log WARN "sudo -n is not available; skipping nix-collect-garbage"'
    '  fi'
    'else'
    '  log INFO "nix-collect-garbage not found; skipping Nix GC"'
    'fi'
    ''
    'if have fstrim; then'
    '  if sudo_ready; then'
    '    log INFO "Running fstrim to return freed blocks to the host"'
    '    if [ "$FREE_DRY_RUN" = "1" ]; then'
    '      log INFO "dry-run: would run sudo -n fstrim -av"'
    '    else'
    '      sudo -n fstrim -av'
    '    fi'
    '  else'
    '    log WARN "sudo -n is not available; skipping fstrim"'
    '  fi'
    'else'
    '  log INFO "fstrim not found; skipping trim"'
    'fi'
    ''
    'log INFO "Guest disk usage after cleanup:"'
    'df -h /'
    'log INFO "Guest cleanup complete"'
  ] | str join "\n"
}

def main [
  instance_name: string
  --dry-run
] {
  let instance_dir = ($env.HOME | path join ".lima" $instance_name)
  let disk_path = ($instance_dir | path join "disk")

  if not ($disk_path | path exists) {
    error make { msg: $"Instance disk not found: ($disk_path)" }
  }

  log INFO $"Preparing cleanup for Lima instance ($instance_name)"
  if $dry_run {
    log INFO "Running in dry-run mode; no guest files will be removed"
  }

  run-command "Host disk allocation before cleanup" { ^du -sh $disk_path }
  run-command "Host disk logical size before cleanup" { ^ls -lh $disk_path }
  run-command "Guest root filesystem usage before cleanup" { ^limactl shell $instance_name -- df -h / }

  let guest_script = (build-guest-script $dry_run)
  run-command $"Guest cleanup for ($instance_name)" { ^limactl shell $instance_name -- sh -lc $guest_script }

  run-command "Host disk allocation after cleanup" { ^du -sh $disk_path }
  run-command "Host disk logical size after cleanup" { ^ls -lh $disk_path }
  run-command "Guest root filesystem usage after cleanup" { ^limactl shell $instance_name -- df -h / }

  log INFO $"Cleanup finished for ($instance_name)"
}
