#!/usr/bin/env nu
# Export/import Codex histories and workspaces through the clean guest runtime.
use chats/core.nu *
use chats/archive.nu *
use chats/export.nu *
use chats/import.nu *

const source_dir = path self | path dirname

def guest [instance: string args: list] { invoke ([limactl shell $instance --] | append $args) }
def remote-worker [instance: string body: closure] {
  let remote = '/tmp/scrubs-chats-' + (random uuid)
  guest $instance [mkdir -m 700 $remote] | ignore
  try {
    for name in [chats.nu chats-schema.json] { invoke [limactl copy ($source_dir | path join $name) $"($instance):($remote)/($name)"] | ignore }
    invoke [limactl copy -r ($source_dir | path join chats) $"($instance):($remote)/chats"] | ignore
    let result = (do $body $remote)
    guest $instance [rm -rf $remote] | ignore
    $result
  } catch {|e| guest $instance [rm -rf $remote] | ignore; error make $e }
}
# Snapshot all task histories and their workspaces. The source stays intact.
def 'main export' [instance: string artifact: path] {
  let out = (lexical $artifact)
  if (exists $out) { fail $"Artifact exists: ($out)" }
  remote-worker $instance {|remote|
    guest $instance [/run/current-system/sw/bin/nu --no-config-file ($remote + '/chats.nu') _export ($remote + '/archive.tar.gz')] | ignore
    # Stage beside output so no-clobber hard-link publication works across disks.
    let temp = (invoke [mktemp -d ($out + '.incoming.XXXXXX')])
    try {
      let incoming = ($temp | path join archive.tar.gz)
      invoke [limactl copy $"($instance):($remote)/archive.tar.gz" $incoming] | ignore
      let report = (inspect-archive $incoming)
      invoke [chmod '600' $incoming] | ignore
      invoke [ln $incoming $out] | ignore
      rm -rf $temp
      {artifact: $out sha256: (digest $out) threads: ($report.threads | length) missing: $report.missing}
    } catch {|e| rm -rf $temp; error make $e }
  } | to json
}
# Verify checksums and list the captured tasks and workspace roots.
def 'main inspect' [artifact: path --json] {
  let report = (inspect-archive (lexical $artifact))
  if $json { $report | to json } else {
    print $"($report.threads | length) tasks; ($report.roots | length) workspace snapshots; ($report.codex_version)"
    print $report.threads
    print $"Missing paths: ($report.missing | to json --raw)"
  }
}
# Merge an archive. Optional mappings are positional OLD=NEW pairs.
def 'main import' [instance: string artifact: path ...maps: string --dry-run --allow-missing-workspaces --preserve-malformed: path] {
  let archive = (lexical $artifact)
  inspect-archive $archive | ignore
  remote-worker $instance {|remote|
    invoke [limactl copy $archive $"($instance):($remote)/archive.tar.gz"] | ignore
    mut flags = ([] | append (if $dry_run { [--dry-run] } else { [] }) | append (if $allow_missing_workspaces { [--allow-missing-workspaces] } else { [] }))
    if $preserve_malformed != null {
      invoke [limactl copy (lexical $preserve_malformed) $"($instance):($remote)/preserve-malformed.json"] | ignore
      $flags = ($flags | append [--preserve-malformed ($remote + '/preserve-malformed.json')])
    }
    guest $instance ([/run/current-system/sw/bin/nu --no-config-file ($remote + '/chats.nu') _import ($remote + '/archive.tar.gz')] | append $maps | append $flags) | from json
  } | to json
}
# Roll back an interrupted guest import.
def 'main recover' [instance: string] {
  remote-worker $instance {|remote| guest $instance [/run/current-system/sw/bin/nu --no-config-file ($remote + '/chats.nu') _recover] | from json } | to json
}
def 'main _export' [artifact: path] {
  let home = ($env.HOME | path expand)
  with-lock ($home | path join .codex .scrubs-chats.nu-lock) {
    quiet
    let result = (export-data $home (lexical $artifact) (invoke [/run/current-system/sw/bin/codex --version]))
    quiet
    $result
  } | to json
}
def 'main _import' [artifact: path ...maps: string --dry-run --allow-missing-workspaces --preserve-malformed: path] {
  let home = ($env.HOME | path expand)
  with-lock ($home | path join .codex .scrubs-chats.nu-lock) {
    quiet
    let acknowledged = if $preserve_malformed == null { {} } else { open $preserve_malformed }
    import-data $home (lexical $artifact) $maps (invoke [/run/current-system/sw/bin/codex --version]) (open ($source_dir | path join chats-schema.json)) --dry-run=$dry_run --allow-missing-workspaces=$allow_missing_workspaces --before-install { quiet } --preserve-malformed $acknowledged
  } | to json
}
def 'main _recover' [] {
  let home = ($env.HOME | path expand)
  with-lock ($home | path join .codex .scrubs-chats.nu-lock) { quiet; recover-data $home } | to json
}
def main [] { help main }
