# Wayforge OpenRig integration

Dotfiles owns the VM/runtime integration only. The canonical crew configuration,
workflow, model policy, budget enforcement and repository/worktree hygiene live
in the separate guest repository at `/home/jem/wayforge-rig`. Consult that
repository's `README.md` and `SETUP.md` for its documentation and operational
status. It has no remote yet, so no remote link is provided here.

## Runtime package

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

## Integration contract and activation boundary

- Dotfiles owns the pinned clean CLI, its opt-in NixOS module and the existing
  clean/dirty execution boundary. It does not own crew seats, model preferences,
  workflow policy, budget state, GitHub adapters or cleanup implementation.
- The rig repository consumes the clean CLI and must validate its native
  launch/hook contracts against this pinned version. Installing the package is
  not proof of budget enforcement, safe session handover or operational workflow.
- Before activation, verify clean Claude/Codex wrapper resolution and that dirty
  tools cannot reach the runtime or credentials. Review any service environment
  or narrowly scoped integration separately; do not broaden sandbox access.
- Runtime deployment, native session/hook enforcement and an end-to-end rig test
  remain separate activation gates. Current implementation gaps and the crew's
  operating policies belong in the rig repository's `SETUP.md`, not this module.

This integration does not clone or replace the rig repository, register projects,
copy secrets into Nix/Git, or activate any daemon, agent, collector or cleanup
timer. No running NixOS configuration has been switched by this PR.

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
