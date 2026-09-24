# Codex chat portability

`vms/chats.nu` exports a guest's Codex conversations and associated workspaces
into one inspectable `.tar.gz` file. Import merges that snapshot into another
guest. Export never deletes the source, and import refuses conflicting files
or conversation identities.

This is an experimental, version-specific adapter for **Codex 0.154.0**.
The original round trip was validated with 0.153.3 on disposable scrubs guests;
the 0.154.0 adapter additionally preserves the nullable `originator` and
`daybreak_enabled` task fields. Both source and destination must use the adapter
version for import. The checked-in `chats-schema.json` contains native schema
definitions and migration checksums, not user data. It lets a completely empty
destination initialize its databases without running a model. Archive-provided
SQL is never executed; its table definitions must match the destination schema.

## Prerequisites

- Run the host commands from this dotfiles checkout, with Nushell 0.115+,
  SQLite, tar, gzip, Git, and Lima. No Python runtime is required.
- Bootstrap the destination normally so it has its own clean configuration and
  credentials. Guests use the clean Nushell and SQLite packages included in
  scrubs. The desktop worker uses macOS launchd.
- Disconnect the affected host in the Codex app and close its CLI sessions.
  Keep workspace writers stopped until transfer finishes. The worker refuses
  to run while a Codex process is present; it does not interrupt tasks for you.
- Use the canonical guest `~/.codex`. Custom Codex/database locations are not
  supported by this adapter.

For maintenance, `touch ~/.codex/scrubs-migration-paused` prevents the scrubs
Codex wrapper from accepting new connections (except `--version`). It does not
stop existing servers: first verify that their loaded-task list is empty and
close them normally. Remove the marker after verification to reconnect. The
native read-only validation helper accepts `--maintenance` while this guard is
in place.

## Export first

```sh
just scrubs-chats-export old-guest ./old-guest.chats.tar.gz
just scrubs-chats-inspect ./old-guest.chats.tar.gz
```

Export copies the worker into a private temporary location, runs it in clean
space through `limactl shell`, retrieves the compressed snapshot, checks all
payload hashes, and publishes the host artifact without replacing an existing
file. A failed export never publishes a partial host artifact. Artifacts are
mode `0600`. For a machine-readable inventory:

```sh
nu --no-config-file vms/chats.nu inspect ./old-guest.chats.tar.gz --json
```

The inventory lists names, IDs, project paths, archive status, last activity,
and missing paths. It does not attempt to infer whether a conversation is
finished. Open and archived conversations are both exported, as are saved
forks and indexed subagent relationships. The exporter also scans session
files for conversations absent from the database index.

## Preview and import

The source home directory maps to the destination home automatically. Explicit
prefix mappings handle projects moving to new locations; the longest matching
prefix wins. Codex's own storage maps to the destination `~/.codex`.
Mappings are positional `OLD=NEW` arguments after the archive filename.

```sh
nu --no-config-file vms/chats.nu import new-guest ./old-guest.chats.tar.gz \
  /home/jem/n64-2048=/home/jem/projects/n64-2048 \
  /home/jem/n64-2048-side=/home/jem/projects/n64-2048-side \
  --dry-run

nu --no-config-file vms/chats.nu import new-guest ./old-guest.chats.tar.gz \
  /home/jem/n64-2048=/home/jem/projects/n64-2048 \
  /home/jem/n64-2048-side=/home/jem/projects/n64-2048-side
```

For unchanged project paths, `just scrubs-chats-import new-guest ARCHIVE` is
the shorthand. Destination workspaces must be inside the destination home.
An existing workspace must exactly match the mapped snapshot; otherwise use
an empty destination path. Repeating an identical import makes no changes.
If either copy has evolved, import reports a conflict and leaves it untouched.
There is intentionally no force-overwrite flag or divergent-history merge.

Malformed rollout JSON is refused by default. If the source already contains
damaged history, retain its original archive and first verify the affected task
through native Codex's `thread/turns/list` with `itemsView: "full"`, including
its saved turn/item IDs. An operator can then explicitly preserve that exact
file with `--preserve-malformed acknowledgements.json`. This JSON object maps
paths relative to `.codex` (for example `sessions/.../rollout-....jsonl`) to their
full-file SHA-256 digests. The importer verifies those digests, reports each
malformed line's byte position, and copies every byte unchanged. It still
checks all indexed offsets, refuses malformed initial metadata, refuses any
path/content rewrite of acknowledged files, and rejects unused acknowledgements.
This preserves existing damage; it does not reconstruct missing events.

Reconnect Codex, add the destination project if necessary, and reopen the
imported conversations. Import preserves IDs; it does not register SSH hosts
or transfer the desktop app's host-local sidebar/global-state files.

### Moving tasks already known to this desktop

Importing identical task IDs onto another guest can leave the desktop's saved
project assignments and cached source-host catalog entries pointing at the old
guest. Restarting alone does not move those saved associations. Native
`thread/read` success is therefore insufficient to establish sidebar visibility.
The app's saved remote-project IDs are also distinct from native app-server
project IDs; `project/import` does not update desktop remote-project assignments.

The desktop step is now generated from the export; no hand-written task IDs or
project IDs are needed. After importing the archive, connect the destination
host in Codex so its catalog discovers the imported tasks. Then run:

```sh
just scrubs-chats-desktop-plan ./old-guest.chats.tar.gz old-guest new-guest ./desktop-plan.json
nu --no-config-file vms/chats-desktop.nu preview ./desktop-plan.json
just scrubs-chats-desktop-arm ./desktop-plan.json
```

The planner discovers the local desktop catalog and application bundle, reads
saved projects, and groups active interactive tasks by destination project and
working directory. Missing destination projects are included in the plan and
created when it applies. Multiple projects and linked worktrees are supported.
An ambiguous catalog/app requires explicit `--catalog` / `--app-bundle`.
Pass the same absolute `OLD=NEW` arguments used for import to the Nushell
`prepare` command when paths change. An absent source project, unknown task
source, unexpected assignment, or missing destination catalog task fails the
plan instead of silently dropping a task. Archived and internal histories stay
in the guest; the plan reports why they are excluded from sidebar assignment.

The desktop may cache only recent tasks even after connecting. In that case,
save the successful native verification result and supply it to `prepare`:

```sh
nu --no-config-file vms/tests/verify-chats-live.nu new-guest ./old-guest.chats.tar.gz > ./native-report.json
nu --no-config-file vms/chats-desktop.nu prepare ./old-guest.chats.tar.gz old-guest new-guest ./desktop-plan.json --native-report ./native-report.json
```

Use a fresh report from the destination with the same path mappings. Every
interactive task must have a matching verified ID and destination directory.
The planner captures existing source catalog metadata for missing destination
entries. The offline worker inserts those entries in the same transaction that
removes their source copies, after checking the schema and unchanged source
rows. It never overwrites an existing destination entry or invents history.

`arm` starts a launchd-owned worker with a 15-minute deadline and prints its job
label, PID, and log path. **Quit Codex completely once; it reopens after the repair finishes.**
The deadline is time allowed to quit, not time to leave the app closed. The
worker holds a lock so two repairs cannot run together. It backs up the desktop
state and catalog, updates only planned project assignments, and removes only
the selected duplicate source-host catalog rows. Guest histories are untouched.
It refuses to modify these stores while the app is running.
The transient launchd job removes itself after completion or failure.

For several source guests, prepare one plan per guest and save their absolute
filenames as a JSON array. Then arm one worker for the whole batch:

```sh
nu --no-config-file vms/chats-desktop.nu arm-batch ./desktop-batch.json --reopen
```

The batch checks all plans against the cumulative desktop state before writing,
holds one migration lock, applies each plan with its own backup, and reopens the
app only after every plan succeeds. Do not arm separate reopening workers for
the same desktop. After an interrupted batch, verify each plan and inspect its
journal; completed plans are idempotent, while interrupted plans retain their
normal recovery procedure.

After reopening:

```sh
just scrubs-chats-desktop-verify ./desktop-plan.json
```

Verification checks every planned destination catalog record and project
assignment and confirms the stale source entries are absent. It exits nonzero
if anything remains. Also confirm the project appears in the sidebar; native
history reads and desktop catalog checks cover different parts of migration.
A repeated completed plan is a no-op, including `arm` (no app restart).

For an interrupted repair, close the app and run
`just scrubs-chats-desktop-recover ./desktop-plan.json`. The journal restores
only the affected state and source catalog rows, and removes unchanged catalog
entries added by the repair. Recovery refuses to overwrite
later desktop changes or roll back a completed migration. Retain the backups
and prepare a fresh plan with a new output filename before retrying a recovered
or timed-out attempt. Plans and worker logs are private files and never replace
an existing file silently.

### Repeatable migration sequence

1. Provision the destination guest's runtime/services with scrubs, at the Codex
   adapter version. Stop source workspace writers and Codex connections.
2. Export and inspect the archive. Keep the source guest and artifact intact.
3. Import with `--dry-run`, then import normally, using identical path mappings.
4. Run `nu --no-config-file vms/tests/verify-chats-live.nu NEW-GUEST ARCHIVE` with those same
   mappings, and validate the project's build/tests in the destination runtime.
5. Connect the destination in the desktop app; prepare and arm the desktop plan.
6. Quit once, let the worker reopen the app, run desktop verification, and check
   the sidebar. Only then consider separately retiring the source guest.

These commands automate the task-storage and desktop-ownership layers. Project
services, tool versions, secrets provisioning, and guest deletion remain
separate explicit operations. Do not call native `project/import` as a
replacement for the desktop step: its project IDs belong to another store.

## What is preserved

- Active and archived JSONL conversation histories, including fork metadata.
- SQLite thread metadata, names, pin/section and project associations,
  dynamic-tool definitions, artifacts, and indexed parent/child relationships.
- Paginated turn/item history and its offsets. Structured paths are remapped
  and byte offsets recalculated when JSONL encoding changes. Historical prose
  and embedded shell commands are not globally rewritten.
  Unchanged rollout lines retain their original bytes. Shared-history streams
  and their base files are supported when their contents need no path changes;
  relocation that would rewrite such a chain is explicitly refused.
- Goals, with active goals paused on arrival so import does not resume work
  automatically. Existing paused/complete/blocked statuses remain unchanged.
- Codex-managed attachments, generated images, and visualizations in the
  supported directories; session index and CLI history are merged.
  The known pasted-text attachment index is merged by attachment path, with
  paths and excerpt-map keys remapped. Conflicting excerpts, unknown index
  schemas, and pending removal queues are refused rather than overwritten.
- Entire discovered Git workspaces, their common Git directories, and
  registered worktrees: local branches/objects, index, staged/unstaged changes,
  untracked and ignored files, and symlinks. Git worktree pointers are repaired.
  Ordinary non-Git project directories are captured too.

The archive is a snapshot, not a live synchronization service. Repositories
with external Git object alternates are marked incomplete. Missing workspaces,
whole-home working directories, clean credential surfaces, and directories
outside the guest home are reported rather than copied indiscriminately.
Registered Git worktrees owned by the guest user beneath `/tmp` or `/var/tmp`
are also captured; map these to a destination inside the home directory.
Conversation history is still exported when a workspace cannot be captured.

Import refuses incomplete archives by default. If the reported workspace
omissions are intentional, `--allow-missing-workspaces` explicitly accepts
them; it never permits missing conversation history. The report retains those
omissions, and absent project files must be restored separately before use.

Not included: authentication, sealed secrets, SSH keys, provider/MCP config,
plugin installation state, memories, telemetry, automation/queued execution,
live terminals, or arbitrary files referenced only in conversation text outside
the captured directories. Re-provision tools/configuration on the destination.
Repository files and conversation text can themselves contain sensitive data;
the archive is compressed, not encrypted.

## Integrity and recovery

Archive inspection rejects traversal, unexpected payloads, special files,
duplicate members, symlink traversal, and checksum mismatches. Symlinks are
preserved without following them. Import preflights every workspace, history
file, schema, and row conflict before installing anything. SQLite is copied
through its backup API, including committed WAL data; source databases are
never replaced wholesale over populated destination databases.

The guest lock prevents concurrent scrubs transfers. Import keeps a rollback
journal and consistent backups of changed destination databases/index files.
Locks use atomic directory creation and recorded process identities. A dead
owner can be reclaimed; a lock with no readable owner requires inspection.
Ordinary installation failures roll back immediately. After an interrupted
process, disconnect Codex and run:

```sh
just scrubs-chats-recover new-guest
```

Recovery only handles this tool's pending import journal. A committed journal
is cleaned up without undoing the import. This does not replace a VM backup
against disk loss or filesystem corruption.

## Validation

```sh
just scrubs-chats-test
```

The offline suite covers clean export, named history, remapping and pagination
offsets, empty and populated targets, repeat import, divergent history,
workspace/metadata conflicts, schema-version refusal, corrupt/malicious
archives, concurrent transfer refusal, rollback, and interrupted-import recovery.
It also checks literal and Unicode filenames, file modes, null values, SQLite
backup rowids, active-goal pausing, and external symlink handling.

The Nushell port keeps format-1 archives and existing desktop plan/journal
formats compatible. The earlier Python implementation is retained in Git at
`5f9bf8d`; executable scripts and tests now use Nushell. See
[the Nushell validation record](chat-portability-nushell-validation.md).

Live validation used two guests provisioned with:

```sh
SCRUBS_CPUS=2 SCRUBS_MEMORY=4GiB \
  nu vms/bootstrap.nu scrubs-chat-source tailscale-disabled
SCRUBS_CPUS=2 SCRUBS_MEMORY=4GiB \
  nu vms/bootstrap.nu scrubs-chat-target tailscale-disabled
```

The fixture repository was `jeremybanka/n64-2048`. Luna generated a documentation
draft and small conversations with private recall markers. The experiment
covered an archived conversation, a paused goal, a saved fork, linked Git
worktrees, and a pre-existing destination conversation. Native app-server
reads and actual Luna resumes verified restoration, including rebuilding
completely blank Codex databases. See [the validation record](chat-portability-validation.md).

`tests/codex-rpc.nu` provides the small stdio app-server client used for these
checks. After an import, reopen every archived and active conversation through
native Codex APIs without generating a model response:

```sh
nu --no-config-file vms/tests/verify-chats-live.nu new-guest ./old-guest.chats.tar.gz
```

For edited prompts that retain multiple rollout files under one stable task ID,
verification checks the current canonical turn/item IDs and the checksums of
the retained older sessions. Superseded turns remain in their original files;
they are not expected to appear as current turns in the native task view.

Pass the same `OLD=NEW` options used during import. This verifies stored
IDs, names, project paths, history paths, fork ancestry, and readable turns.
Validate a new Codex version in disposable guests before extending the
schema adapter; changing the version string alone is insufficient.
