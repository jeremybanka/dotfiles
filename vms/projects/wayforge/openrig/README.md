# Wayforge OpenRig integration

Wayforge owns the crew, but **the crew is its own repository**:
`/home/jem/wayforge-rig` in the guest. Dotfiles owns the Scrubs platform integration,
not the crew's evolving prompts, queues, budget ledger or worktrees. The
[working plan](PLAN.md) records the design; the guest repository's `SETUP.md`
records its current installation and activation gaps.

## Current state

On 13 November 2026 the guest repository was initialized on `main` at `b35a44d`
with 14 seats, independent Codex/Claude budget controllers, and cautious
worktree-retirement tooling. It has no remote yet. Its pinned dirty npm install
is useful for schema checks, **not** a clean agent-launch runtime. Tests and
schema validation are not proof that real native sessions obey budget admission.
Neither a daemon, provider timer, cleanup timer nor crew has been started.

This integration supplies a reproducible **clean-runtime package**, pinned to
`@openrig/cli` 0.7.3 and a complete public npm dependency lock. It does not copy
`node_modules` out of a writable working repository. Nix obtains dependencies by
integrity hash, builds in its sandbox and makes the result immutable. The build
checks the CLI version and exercises SQLite in memory against the packaged Node
ABI. The package contains the `rig` CLI, not an `openrig-tui` launcher.

## Opt-in package, no automatic activation

The Wayforge shim imports `module.nix`. The option defaults to false:

```nix
programs.wayforge-openrig.enable = true;
```

Enabling it in a reviewed guest configuration adds the pinned `rig` executable to
clean system packages. It does **not** start a daemon, create model sessions,
install native hooks, select budgets, modify credentials, change dirty sandbox
allowlists or alter the isolated Wayfarer CI account. This PR has not switched the
running NixOS configuration. Review that promotion into the trusted runtime
before applying it.

Agent execution must continue using the existing clean Claude/Codex launch paths.
Never expose their binaries, credentials or sealed-auth helpers to dirty Node.
No daemon service is provided yet: its launch environment and native hooks must
be validated together, not bypassed with a broad PATH or credential mount.
The CLI's presence alone does not establish safe agent launch or effective
budget enforcement.

## Remaining activation gates

1. Apply the reviewed clean package to the developer environment; verify clean
   agent-wrapper resolution and absence from dirty space. Never substitute the
   repository's npm dependency for the trusted runtime.
2. Wire and test provider-native hooks in actual seat workspaces. Cover stable
   session/turn identity, start/stop/interruption/compaction and child launches.
   Denial or missing identity must stop admission, not fabricate a permit.
3. Bind each controller to its provider/account and select allowance windows and
   concurrency. Floors are supplied per factory opening: `50/40` means Codex
   50% remaining and Claude 40% remaining, not permanent defaults. Both start
   disarmed. The first provider floor or reset pauses new admission across the
   factory without forcibly cancelling existing turns; reopening is explicit. No
   cross-provider fallback or summed percentages.
4. Verify a fresh, account-bound Claude quota source. Status-line samples alone
   remain observation-only; automatic Haiku probing is not enabled. Codex's
   one-shot native quota read was tested without a model turn, but no persistent
   collector is installed here.
5. Exercise one small implementation and independent Warden review/integration
   flow before expanding concurrency. The factory works queued items and opens
   reviewed stacked PRs for Jeremy to merge; it does not merge or deploy.
6. Validate task closure and Deckhand cleanup holds. Dirty/untracked files,
   unique/unpushed commits, locked or active trees and uncertain evidence prevent
   retirement. No age-based forced deletion or cleanup timer is installed.

The guest repository remains the source for `CULTURE.md`, `SOP.md`, role guidance,
project catalog, budget code and hygiene code. Publish it separately only when a
remote and publication scope have been chosen. This PR does not invent a remote,
clone on boot, replace the guest repository, or copy secrets into Nix/Git.

## Package validation

Run on a Linux Nix builder with this checkout available (the guest is
`aarch64-linux`). These commands evaluate/build only; they do not switch NixOS or
start OpenRig:

```sh
nix eval --impure --json --expr '
  let f = builtins.getFlake (toString ./vms);
      pkgs = import f.inputs.nixpkgs { system = "aarch64-linux"; };
  in import ./vms/projects/wayforge/openrig/test-module.nix { inherit pkgs; }'

nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake (toString ./vms);
      pkgs = import f.inputs.nixpkgs { system = "aarch64-linux"; };
  in pkgs.callPackage ./vms/projects/wayforge/openrig/package.nix {}'
```

When updating OpenRig, regenerate `runtime/package-lock.json` from the exact
package manifest without executing dependency scripts on the host, refresh
`npmDepsHash`, build on the guest architecture, and rerun native ABI and boundary
checks. An upstream CLI release does not automatically make hook contracts or
budget adapters compatible.
