# Wayforge expedition: working plan

Status: design draft, updated 13 November 2026. This is a working plan, not a deployed
rig, executable permission policy, or authorization to launch a crew.

## Purpose and ownership

Wayforge owns one OpenRig expedition serving the repositories developed in its
Scrubs VM. Repositories supply their own intent, instructions, tasks, and proof;
Wayfarer does not own a separate rig by default. The expedition is a crewed ship:
its direction, planning, execution, review, and housekeeping are distinct jobs.

Wayforge currently hosts both development and isolated Wayfarer CI. They could
be separate VMs later. Today the crew belongs on the developer side, not in the
`wayfarer-ci` account or `/var/lib/wayfarer-ci-work`. Preserve separate accounts,
credentials, workspaces, and the Scrubs clean/dirty execution boundary. Shared
CPU, memory, disk, database, and ports still need coordination.

Versioned crew source belongs here beside the [Wayforge shim](../README.md).
Runtime queues, sessions, telemetry, and working copies belong in guest runtime
storage, not Git. No guest installation or readiness is established by this
plan. Role names describe responsibilities, not mandatory always-running model
sessions or new privileges.

## Crew manifest

The latest names replace the earlier party terminology:

- Raid Leader becomes **Captain**.
- Quest Giver becomes **Commander**.
- Wizard becomes **Sky Command**.
- Bard becomes **Chronicler**.
- Ranger is omitted for now. Each task still includes the reconnaissance it
  needs; no separate scouting seat is required.

Only the implementation pool's counts have been selected. Other role names do
not yet settle concurrency, models, or whether a seat is continuously occupied.

| Role                     | Responsibility and output                                                                                                                          | Boundary                                                                                                                                                       |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Commander                | Liaison with Jeremy: preserve intent, corrections, priorities, and the conversation; return outcomes and obtain necessary decisions.               | Does not replace Jeremy as the source of intent or silently turn an observation into approved work.                                                            |
| Captain                  | Admit, allocate, sequence, and recover work; coordinate resources and continuations across repositories.                                           | Coordinates execution, rather than redefining intent or granting publication authority.                                                                        |
| Sky Command              | Architecture and bounded planning: turn intent into compatible slices, acceptance criteria, dependencies, and evidence requirements.               | Plans from evidence; does not treat a spike as a production commitment.                                                                                        |
| **2 Striders**           | Standard implementors, producing positive diffs that build the requested capabilities.                                                             | Separate task-owned worktrees; independently reviewed candidates. Positive diff is a work direction, not a line-count reward.                                  |
| **1 Lancer**             | Builds “parodies” of existing code from a particular stance or position; may target a positive or neutral delta.                                   | Each assignment must state its stance, what existing code it responds to, and how the result should be evaluated. A parody is not automatically a replacement. |
| **1 Pyro**               | Produces net-negative deltas by simplifying code and removing unnecessary machinery.                                                               | Preserve required behavior and evidence. Smaller code is not a reason to remove obligations, tests, or useful diagnostics.                                     |
| Witch                    | Bounded experiments, factual probes, comparative measurements, and prototypes.                                                                     | State question, baseline, variables, budget, and stopping condition; return reproducible evidence and limitations.                                             |
| Cleric                   | Developer experience for the crew: tooling, configuration validation, reproducibility, diagnostics, and prevention of recurring workflow failures. | Heals the workflow; does not become the default janitor or get blanket infrastructure privileges.                                                              |
| Hierophant               | Own genuine unresolved questions through investigation, human judgment, reconciliation, and a scoped continuation.                                 | Research answerable facts first. Do not resume execution from a raw answer before reconciling its implications.                                                |
| Chronicler               | Keep decisions, rationale, documentation, and results coherent and understandable.                                                                 | Commander owns the direct relationship and original intent; Chronicler makes the record useful without duplicating questions.                                  |
| Inquisitor               | Investigate major bugs, locate the responsible subsystem, and explain underlying causes across system boundaries.                                  | Diagnosis, not merely devil's advocacy or routine candidate review.                                                                                            |
| Warden                   | Independently evaluate exact candidate revisions in the refinery against real goals and acceptance criteria.                                       | Does not certify its own substantive repairs. Review acceptance is not merge or publication authority.                                                         |
| Deckhand (proposed name) | Swab the deck: track task-owned worktrees, verify safe retirement, and keep the ship free of abandoned working copies.                             | Never discard unique uncommitted work merely because it is old. The name is a proposal; the cleanup responsibility is requested.                               |

Knight is removed as a separate seat. Bug fixes and hardening return to the
responsible implementor, normally a Strider, with Inquisitor available for major
root-cause investigations and Warden for independent review. Lancer's “parodies” wording
is deliberate: the first task should make the particular stance concrete rather
than silently narrowing it to a generic rewrite or adversarial test role.

## Work lifecycle and handoffs

1. **Intake:** Commander captures Jeremy's goal, constraints, and later changes.
2. **Plan:** Sky Command checks existing decisions and code, then defines bounded
   work and its proof. Hierophant takes custody of unresolved judgment.
3. **Admit:** Captain checks permissions, provider capacity, shared resources,
   and dependencies, then allocates a named task and continuation owner.
4. **Work:** a Strider or specialist receives an explicit repository, base
   revision, isolated worktree, scope, acceptance criteria, and stop conditions.
5. **Refine:** Warden examines the exact candidate revision and its evidence.
   Defects return to the responsible worker, normally a Strider. Inquisitor takes major
   causal uncertainty; Witch tests a specific hypothesis; Hierophant owns
   decisions that evidence alone cannot settle.
6. **Integrate:** an explicitly designated integration owner serializes accepted
   changes and verifies the resulting revision. This owner remains to be chosen;
   Warden's review is not implicit authority to merge, push, publish, or deploy.
7. **Close:** Commander returns the outcome; Chronicler preserves the useful
   record; the worker and Deckhand complete or explicitly hold cleanup.

The refinery is an evaluation stage, not merely a merge queue. It can produce
acceptance, a concrete repair request, missing evidence, or a question. A
substantive evaluator-authored repair needs another independent evaluator.

Every handoff records goal, repository, revisions, task/worktree ownership,
constraints, evidence, unresolved issues, and next owner in durable work records.
Messages alone are not the task ledger. If a question blocks one task, unrelated
admitted work can continue. Hierophant preserves the answer with its explanatory
context, reconciles it with Sky Command, and returns a scoped continuation via
Captain.

## Warden compared with the CS16ND Refinery

These have the same core purpose: independent judgment of candidate work. In
CS16ND, **Refinery is an actual seat** (`dev.review`, profile `refinery`), not only
a stage name. Its guidance owns both independent review **and final integration**
in a separate checkout. It receives an exact worker revision and criteria, queues
repairs without editing the worker's tree, and must not independently certify its
own substantive repair.

The CS16ND seat also holds the integration slot, rebases onto the current target,
runs affected QA on the resulting revision, and performs an authorized merge.
Changed post-rebase revisions require matching evidence. Review, retry, QA, and
integration each require admission; builds and emulator captures are serialized.
Accepted proof still does not grant publication authority.

Warden currently matches the independent-review portion, while this plan leaves
integration ownership open. Thus the closest description is **the same kind of
seat, but CS16ND's Refinery has a broader integration remit**. The expedition's
refinery remains the workflow stage; Warden is its named responsible reviewer.

A natural next choice is to let Warden own review plus serialized integration,
following CS16ND rather than adding another seat. That is a recommendation, not
a settled expansion of this plan or permission to merge. Keep Inquisitor's causal
investigation distinct, and preserve independent evaluation after substantive
repairs regardless of who holds the integration role.

Evidence inspected on 13 November: CS16ND
`openrig/agents/team/guidance/refinery.md` (lines 3–14),
`openrig/rig.yaml` (the `dev.review` member), and
`openrig/factory/README.md` (Work and questions). Local HEAD was `80c2582`; the
refinery guidance matched that commit. The rig and factory README contained
existing uncommitted changes, which were read but not modified. This comparison
is about declared responsibility, not a claim about current running occupants.

## Deckhand and the spirit of hygiene

The aim is low clutter and few recurring judgment calls, while keeping primary
checkouts clean for humans. Remote-pushed, verified work is durable; local
working copies can be disposable once their unique contents have a safe home.
“Done” includes housekeeping, not a second forgotten janitorial task.

The earlier Claude hygiene proposal used seven-day idle expiry, including dirty
worktrees. This plan preserves its intent but **does not adopt automatic deletion
of dirty worktrees**. Age is a reason to inspect, not evidence that work is
worthless or recoverable. A clean status alone also does not prove that local
commits exist anywhere else.

### Proposed procedure

- Create agent worktrees only under each repository's ignored `.worktrees/`
  directory, with stable task identifiers. Do not scatter them through `/tmp`,
  home directories, or duplicate full clones.
- Associate each worktree with its queue task, owner, base, branch, state, and
  intended retention. Record the association when the tree is created.
- Keep scratch in declared `.scratch/` or temporary locations. Do not classify
  an arbitrary untracked file as disposable scratch merely by guessing.
- Paused work remains owned. Record its reason and next review and lock the
  worktree. A lock is a retention signal, not a backup or access-control boundary.
- Task closure, merged or abandoned, requests retirement; it does not blindly
  invoke forced removal. Deckhand checks active processes, locks, worktree
  registration, staged/unstaged/untracked files, and unique local commits.
- Before removal, verify that all work being retained exists at an approved
  durable destination and record its exact revision or recoverable artifact.
  Push only where publication is authorized. Do not upload secrets or unwanted
  files simply to satisfy the cleanup checklist.
- Dirty files, uncertain ownership, unique unpushed commits, or incomplete proof
  produce a **cleanup hold** with an owner and next step. Preserve the tree while
  arranging a reviewed commit, suitable recoverable archive, or explicit discard
  decision. A stash alone is not a verified durable handoff.
- Remove only an inactive tree whose contents are confirmed disposable or
  recoverable, using ordinary worktree removal, not a force-delete fallback.
  Branch deletion is a separate decision. Log what was removed and the evidence
  that made it safe.
- A seven-day idle threshold is a proposed backstop for inspection, not an
  approved destructive timer. Locked/paused trees stay excluded. If capacity is
  exhausted, stop admitting new work and escalate; do not sacrifice held work.
- Inventory idle full clones separately. A worktree sweeper must not silently
  expand into deleting unrelated repositories, caches, or human checkouts.

A task can be substantively delivered while cleanup is held, but must not be
reported as fully retired. Captain retains a tracked cleanup continuation.
Deckhand performs routine checks and retirement; Cleric improves the tooling
when the procedure exposes a recurring failure; Chronicler keeps policy clear.
The worker remains responsible for handing over a clean, attributable result.
No role title substitutes for required deletion approval or proof of recovery.

### Future source layout

When implementing this plan, put common values and “done means clean” in
`CULTURE.md`; put placement, pause/resume, retirement, and sweep procedures in
`SOP.md`. Role guidance should refer to those shared rules rather than copy them.
This draft does not install a cleanup script, timer, hook, or deletion policy.

## Provider usage lifecycle

Carry forward research into Codex and Anthropic usage without treating it as a
launch decision. Jeremy reports that the existing Counter-Strike Codex monitor
works in practice. A historical controller snapshot is not grounds to declare it
broken or change it. Counter-Strike is a reference, not a modification target.

The inspected Codex observer polls native account/quota data without model turns.
Installed OpenRig can consume Claude status-line five-hour and weekly quota
samples, but idle freshness and binding a sample to the active account remain
important limitations. Its alternate account-specific probe uses a Haiku model
turn, so it is not free monitoring. Organization API cost analytics are not an
equivalent personal-subscription balance.

Separate observation, identity, policy, and admission. Preserve source timestamp,
provider, account binding (or explicit uncertainty), allowance window, reset, and
freshness. Do not sum percentages across providers or treat unknown as unused.
Captain consumes admission decisions; Cleric maintains instrumentation; Commander
preserves Jeremy's spending policy. No automatic model probing, account changes,
spending floors, or provider fallback is selected here.

Before activation, test account switches, resets, stale or missing readings,
restart continuity, interrupted permits, shared-account consumption, hook
failures, and in-flight overshoot. Decide how to remain conversational while
operational work is paused. No monitoring is launched by this document.

## Implementation sequence

1. Walk one feature task through Commander, Sky Command, Captain, a Strider,
   Warden, integration, and Deckhand. Exercise a cleanup hold as well as success.
2. Walk a major cross-system bug through Inquisitor, Witch if needed, a Strider,
   Warden, and Hierophant if diagnosis exposes a genuine decision.
3. Choose the first bounded Lancer stance and Pyro simplification; define proof
   that distinguishes useful alternatives or deletion from cosmetic churn.
4. Inspect actual guest readiness and supported OpenRig installation. Model
   dependencies and credential access within Scrubs boundaries; do not give dirty
   tools ambient access to clean credential surfaces for convenience.
5. Author shared culture, SOP, role profiles, and an explicit project catalog.
   Reuse OpenRig seats, profiles, durable work records, and context selection.
   Avoid inventing a parallel RPG task system. Collaboration edges are not
   enforcement of budgets or permissions.
6. Implement cleanup tooling first in inventory/dry-run mode, with fixtures for
   dirty trees, untracked files, unique commits, locked pauses, active workers,
   missing remotes, failed pushes, recoverable archives, and interrupted cleanup.
7. Validate manifests, permission boundaries, usage admission, and resource
   reservations. Launch only under a subsequent authorized activation plan.

## Decisions still open

- Confirm **Deckhand**, or choose another name for the cleanup role.
- Assign integration ownership and define its publication boundary.
- Choose models, provider policy, concurrency, startup/idle behavior, and resource
  limits. Two Strider seats do not by themselves authorize two simultaneous turns.
- Define the initial Lancer stance and what positive/neutral delta means for its
  acceptance criteria; keep the intended “parody” character.
- Set retention/review intervals and approved recovery destinations. Seven days
  is a proposed inspection backstop, not a settled expiry or delete authorization.
- Decide pod boundaries and canonical addresses after testing the handoffs.

## Sources and scope

This plan carries forward Jeremy's 12 November crew discussion, the editable
Wayforge party draft, and the 11 November Claude conversation “Git worktree
cleanup standards.” The latest instruction supersedes the earlier destructive
idle-expiry policy and role names.

Repository anchors: [Scrubs overview](../../../README.md), [Wayforge shim](../README.md),
and the root [agent guidance](../../../../AGENTS.md). Prior analysis read CS16ND's
seven-role local checkout and Wayfarer's team proposal; neither is changed here.
Claude quota references: [status-line contract](https://code.claude.com/docs/en/statusline)
and [usage documentation](https://code.claude.com/docs/en/costs).

This branch adds planning documentation only. It does not deploy a rig, start
agents, modify Counter-Strike, install monitoring, clean any working copies, or
change system/credential permissions.
