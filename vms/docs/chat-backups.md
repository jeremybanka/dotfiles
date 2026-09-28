# Codex chat backups (implementation draft)

The host runs Nushell orchestration and restic 0.19.1. Restic owns encryption,
compression, deduplication, and repository integrity. The existing portability
adapter owns capture validation and reconstructing an importable archive.
The migration files originated in `e7cea05`. Explicit schema adapters now cover
Codex 0.154.0 and 0.157.0; capture and restore must use the same supported version.
The clean guest module includes SQLite. Guests provisioned before that dependency
was added need a normal bootstrap before invoking the backup CLI; the backup
runner does not reach into arbitrary Nix-store paths to find tools.

## Current scope

- Back up Codex histories, task metadata, and chat attachments from an explicitly
  named Lima guest through its clean runtime. Repository files, Git history,
  workspace assets, and worktrees belong to the forge and are not captured.
  All cloud access happens on the host.
- Upload expanded, checksum-verified files, not a repeatedly compressed tarball.
  Stable source names group snapshots independently of guest filesystem paths.
- Record per-source attempts, last successful backup, capture time, snapshot ID,
  task count, and any acknowledged damaged histories. One failed guest does not prevent others
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

Guest backups default to **live capture**. They use SQLite's online
backup API and copy a bounded, complete-line prefix of each JSONL stream. An
unfinished last record stays on the source and is deferred to a later backup;
the manifest records its excluded byte count. Appending tokens can continue.
No process is stopped, disconnected, or signaled, and stopped guests are not
started. Live workers use low CPU and idle I/O priority. Set `capture = "quiet"`
for the original stopped-writer export mode.

Database connections forbid creation of a missing source and issue only read
and backup operations. SQLite may maintain its normal WAL sidecar files; no
application tables are modified by capture.

Live capture retries the entire attempt up to three times if a copied prefix is
rewritten, tree membership changes, attachment bytes change, a JSON
record is malformed, or an indexed byte offset is absent. It validates schema,
foreign keys, resolvable history relationships, and attachment-index state before
publishing an archive. Unassociated history rows are rejected rather than
silently omitted; retained legacy orphan rows may need a separate compatibility
adapter. A failed
capture preserves the previous successful backup.

This is a **validated recovery window**, not an atomic filesystem snapshot.
Each database has its own snapshot; rollout prefixes can include later complete
events, and attachment files are independently copied and rechecked. The manifest
records the window and stream cutoffs. Nothing claims that all task metadata
represents one application transaction. Check `captured_at` as well
as `last_success`: backing up an old archive does not make its contents fresh.

The backup runner always requests `--chats-only`, preserving working-directory
references without reading or copying those directories. Restore code and Git
history from the forge separately. For old migration archives used as backup
sources, the host verifies the archive, then removes workspace payloads and their
manifest entries before uploading. A regular migration export still includes
workspaces; that remains a separate workflow.

Chat text and attachments can themselves contain sensitive material. Codex login
credentials are excluded; this is not a general secret scrubber. Host-local
capture and desktop association backup remain follow-up work.

Live capture estimates staging and archive space before copying payloads, leaving
a 2 GiB reserve plus metadata headroom. Insufficient space fails the attempt.
This check is not a disk reservation; other processes can still consume space.
Disposable manifest writes do not invoke a guest-wide filesystem sync.

### Preserving known damaged histories

Live export refuses malformed JSON by default. After verifying the retained
turns and items through native Codex on an isolated copy, an operator can provide
a private JSON object mapping each affected path relative to `.codex` to its
full-file SHA-256. Configure its absolute path as `preserve_malformed` for a live
guest source, or pass `--preserve-malformed FILE` to `chats.nu export --live`.

The acknowledgement must name a rollout under `sessions/` or
`archived_sessions/`. Capture requires the entire file to match, with complete
trailing bytes and valid initial metadata. Growth, rewrites, stale hashes,
missing files, and acknowledgements of valid files fail. Indexed byte boundaries
and candidate databases are still validated; no record is discarded or repaired.
The manifest and backup status record the exact preserved hashes.

Restore does not automatically trust an archive's acknowledgements. Pass the
verified JSON explicitly to `chats.nu import --preserve-malformed FILE`.
Acknowledged files cannot undergo path/content rewriting; use original task
paths when their contents include them. This preserves existing damage rather
than reconstructing missing events.

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

1. Exercise the validated live capture on representative real task stores and
   verify restored tasks through native Codex in a disposable guest. Synthetic
   concurrent-writer capture and database import are covered now;
   application-level atomicity would require writer cooperation or a filesystem
   snapshot. SQLite's backup API alone does not coordinate all stores.
2. Capture local-host task data and the minimum desktop project associations
   needed to restore the sidebar; exclude unrelated app state and credentials.
3. Add stale-backup notifications and periodic disposable-guest restore checks.
   Exit status and a status file exist now; notifications are not implemented.
4. Validate cloud round trips and recovery with independently held credentials.
   Choose an appropriate protection against deletion, then separately enable
   retention/pruning. Do not apply bucket expiry rules directly to restic objects.
5. Avoid gzip export/re-extraction by factoring verified staging out of the
   migration exporter.

## Validation

`just codex-backups-test` uses synthetic task data and a temporary encrypted
restic repository. It covers unchanged-file deduplication, full repository
checks, archive reconstruction and import, credential exclusion, no-overwrite
restore, independent source failures, retention dry-run, overlapping runs,
wrong passwords, configuration validation, and LaunchAgent plist semantics.
The local suite neither contacts real guests nor configures a cloud bucket or
agent. The live suite has also been run with synthetic stores in wayforge's clean
Linux runtime. It never reads or replaces the guest's real task histories.

`vms/tests/chats-live.nu` covers fixed prefixes, split UTF-8, truncation/rewrite
refusal, missing indexed boundaries, bounded retry, tree edits, both supported
schemas, and capture plus restore while another process writes WAL updates and
appends history. `just codex-backups-test` runs it for both versions, and CI runs
these tests plus the existing migration regression suite.

`vms/tests/chats-preservation.nu` additionally exercises checksum-pinned damaged
histories through live capture, encrypted backup, archive reconstruction, and
explicit import. It checks refusal of changed bytes, partial tails, malformed
metadata, unused pins, and insufficient staging space. The backup integration
test also proves that an older full migration archive cannot upload workspace
files through this runner.

### Real-store rehearsal, 2026-09-28

The first rehearsal against the consolidated wayforge guest did **not** pass
the full backup/restore test. With its Codex processes still running, prefix
preflight checked 1,622 real rollout streams and found one malformed complete
record in a legacy puggers history. There were no incomplete trailing bytes.
The production prefix validator rejects that record without publishing a copy.
The full export was stopped after this deterministic blocker was established;
no real-data backup archive or restic snapshot was produced.

A separate diagnostic restored online database snapshots and that exact,
checksum-verified rollout into a fresh guest running Codex 0.157.0, without
account credentials. Native `thread/read` and paginated `thread/turns/list`
returned all 2 indexed turns and 27 indexed items. This proves that the retained
chat is readable; it does not validate the full archive/import/restic pipeline.
No model was run, and the source histories were not repaired or rewritten.

The rehearsal also exposed repeated Git inspection for chats sharing a project;
capture now discovers each workspace once per attempt. Invalid JSON errors now
identify the file and line without including conversation text.

That rehearsal motivated the checksum-pinned live preservation path above.
Backup scope is now explicitly chat-only: the roughly 27 GB of repository data
seen during that test is the forge's responsibility and will not be staged.
The subsequent chat-only capture completed while wayforge remained in use:
1,606 chats, no workspaces, and a 481 MiB compressed archive. Its transfer checksum
matched. A private local restic repository accepted the expanded payload, passed
`check --read-data`, and reconstructed a verified restore archive. Import into
the disposable `chat-backup-restore` guest restored 57,226 database rows and all
1,606 chat records. The acknowledged damaged rollout remained unchanged. Source
staging was removed after transfer; no source Codex process was stopped.

The native verifier follows edited sessions' shared-history byte cutoffs and
item ordinal limits. Superseded turns and items remain in the retained source
files/database rows but are correctly absent from the current native view.
Regression tests require all in-range items and reject missing visible turns.
Native Codex 0.157.0 successfully read all 1,606 restored chats, including 2,176
visible turns and 53,869 items. Seventeen superseded turns were accounted for in
retained histories. No model was run or account credential installed in the
restore guest.

This is a local encrypted rehearsal; no private cloud or production schedule is
enabled.

References: [restic backup semantics](https://restic.readthedocs.io/en/stable/040_backup.html),
[retention](https://restic.readthedocs.io/en/stable/060_forget.html), and
[Apple LaunchAgent guidance](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html).
