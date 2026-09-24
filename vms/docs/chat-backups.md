# Codex chat backups (implementation draft)

The host runs Nushell orchestration and restic 0.19.1. Restic owns encryption,
compression, deduplication, and repository integrity. The existing portability
adapter owns capture validation and reconstructing an importable archive.
The migration files on this branch are reused from `e7cea05`; this does not
change that adapter's Codex 0.154.0 compatibility boundary.

## Current scope

- Back up verified portability archives or export an explicitly named Lima
  guest through its clean runtime. All cloud access happens on the host.
- Upload expanded, checksum-verified files, not a repeatedly compressed tarball.
  Stable source names group snapshots independently of guest filesystem paths.
- Record per-source attempts, last successful backup, capture time, snapshot ID,
  task count, and workspace warnings. One failed guest does not prevent others
  from being backed up. Any source failure makes the overall run exit nonzero.
- Use a private state directory and a process lock. A partial restic backup is
  a failure; it cannot replace the last successful backup record.
- Restore an explicitly selected snapshot into a new portable archive, verify
  its payload, and refuse to overwrite an existing output. Actual guest import
  and desktop reassignment remain separate, deliberate migration operations.
- Preview retention: 14 daily, 8 weekly, 12 monthly snapshots, grouped by source.
  This draft does not delete snapshots or prune storage automatically.
- Generate or install a daily macOS LaunchAgent without loading it by default.
  Installation copies the runner and its modules into an immutable runtime
  directory, so branch switches and temporary checkout cleanup cannot remove it.

**This is not yet a seamless backup of running Codex tasks.** The guest exporter
requires stopped Codex processes and workspace writers. It does not disconnect
or kill them, start stopped guests, or modify migration pause markers. A busy
or unavailable guest is reported as failed and retains its previous successful
backup. Check `captured_at` as well as `last_success`: repeatedly backing up an
old archive does not make its contents fresh.

Full migration exports retain associated workspaces. They can be large and
include sensitive project files, including project-local secrets. Codex login
credentials are excluded by the migration adapter, but this is not a general
secret scrubber. This draft does not introduce dependency/build-cache exclusion
rules; those need an explicit capture policy before routine deployment.
Host-local Codex capture and desktop association backup are also follow-up work.

## Local rehearsal

Install with `mise install restic`. Copy `vms/backups/config.example.toml` to a
private location outside Git, replace its absolute paths, and run `chmod 600`
on the configuration. For a rehearsal, use an `archive` source and a local
repository. The password can come from a private file or an argv-based host
Keychain command; exactly one is required. Save the recovery password separately
in your password manager. It must remain available after losing the host.

```sh
just codex-backups-init /absolute/path/config.toml
just codex-backups-run /absolute/path/config.toml
just codex-backups-status /absolute/path/config.toml
nu vms/chat-backups.nu snapshots /absolute/path/config.toml
nu vms/chat-backups.nu check /absolute/path/config.toml
just codex-backups-restore /absolute/path/config.toml SNAPSHOT_ID /absolute/path/recovered.tar.gz
nu vms/chats.nu inspect /absolute/path/recovered.tar.gz
```

Repository initialization is explicit. Scheduled runs never initialize a missing
repository. A restored archive can be passed to the existing `vms/chats.nu import`
command, with the usual preview, version checks, and path mappings.

Cloud configuration uses `s3:https://ACCOUNT_ID.r2.cloudflarestorage.com/BUCKET`
and an explicit private host credentials TOML containing `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY`. Optional keys are `AWS_SESSION_TOKEN` and
`AWS_DEFAULT_REGION`. Credentials are loaded only for the restic subprocess;
no credentials are copied to guests or embedded in the LaunchAgent plist.
Cloud upload and retrieval have not been exercised by the local integration test.

## Daily host LaunchAgent

This follows the Helix agent's user-level installation convention, but uses
`StartCalendarInterval` instead of a continuously running `KeepAlive` process.
The default is 03:00 local time; hour and minute are configurable. It does not
wake the Mac or start guests. macOS coalesces calendar events missed during sleep
into a run after wake; a logged-out user does not have an active user agent.
This is a best-effort daily schedule, not an always-on service.

First render a plist anywhere for review:

```sh
nu vms/chat-backups.nu agent-plist /absolute/path/config.toml /tmp/codex-backups.plist --hour 3 --minute 0
plutil -lint /tmp/codex-backups.plist
```

Install a self-contained runtime and a plist under `~/Library/LaunchAgents`:

```sh
just codex-backups-install-agent /absolute/path/config.toml 3 0
```

After a successful manual backup/restore, explicitly load the installed job:

```sh
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.jeremybanka.codex-chat-backups.plist"
launchctl print gui/$(id -u)/com.jeremybanka.codex-chat-backups
```

Alternatively, pass `--load` to `install-launch-agent` when installing. Nothing
is scheduled merely by adding this code. To stop the job:

```sh
launchctl bootout gui/$(id -u)/com.jeremybanka.codex-chat-backups
```

The plist captures the host tool PATH and absolute Nushell/runtime/config paths,
sets a private umask, and writes private stdout/stderr logs under `state_dir`.
It contains no password or cloud credentials. Reinstall after intentionally
changing tool versions or runner code. An existing plist is never silently
replaced. Keep the referenced runtime while a job is installed.

## Before enabling unattended production backups

1. Establish consistent capture across live rollout files and multiple SQLite
   databases, and prove it with concurrent-writer and restore tests. SQLite's
   backup API alone does not coordinate all these stores.
2. Capture local-host task data and the minimum desktop project associations
   needed to restore the sidebar; exclude unrelated app state and credentials.
3. Add an explicit workspace policy for uncommitted files versus regenerable
   dependencies, caches, and project-local secrets.
4. Add stale-backup notifications and periodic disposable-guest restore checks.
   Exit status and a status file exist now; notifications are not implemented.
5. Validate cloud round trips and recovery with independently held credentials.
   Choose an appropriate protection against deletion, then separately enable
   retention/pruning. Do not apply bucket expiry rules directly to restic objects.
6. Avoid gzip export/re-extraction by factoring the verified staging operation
   out of the migration exporter once the capture policy is settled.

## Validation

`just codex-backups-test` uses synthetic task data and a temporary encrypted
restic repository. It covers unchanged-file deduplication, full repository
checks, archive reconstruction and import, credential exclusion, no-overwrite
restore, independent source failures, retention dry-run, overlapping runs,
wrong passwords, configuration validation, and LaunchAgent plist semantics.
It neither contacts real guests nor configures a real cloud bucket or agent.

References: [restic backup semantics](https://restic.readthedocs.io/en/stable/040_backup.html),
[retention](https://restic.readthedocs.io/en/stable/060_forget.html), and
[Apple LaunchAgent guidance](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html).
