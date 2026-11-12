# Wayforge project shim

This shim retains Wayforge's development PostgreSQL setup and also provisions the repository-scoped Wayfarer GitHub Actions runner through `wayfarer-ci.nix`.

## Wayfarer CI

The `github-runner-wayfarer` system service runs as `wayfarer-ci` with home `/home/wayfarer-ci` and a separate work root at `/var/lib/wayfarer-ci-work`. It is enabled at boot and capped at two CPUs of quota and 4 GiB memory. It cannot see the developer home or use sudo, developer credentials, or a Docker socket.

The root-only `wayfarer-ci-home` preparation service copies an explicit allowlist of the already provisioned scrubs runtime and the local Node command-path helper into the CI home. It does not copy clean authentication wrappers, tokens, the developer's mise configuration, or the developer's tool data. The CI account gets the default scrubs policy with `enable_proc: false`, so dependency execution remains sandboxed without relaxing the runner's systemd procfs protections.

Node and pnpm are provisioned from the repository's pins using the CI account's clean mise wrapper. Repository commands use that account's dirty proxies, not `mise exec`. The job-completed hook removes the Wayfarer checkout after action cleanup; tool downloads, action caches, and logs persist. Monitor guest disk usage.

The runner is named `wayforge-wayfarer`, is scoped to `jeremybanka/wayfarer`, and has the custom `wayfarer-ci` label. See [Wayfarer's CI documentation](https://github.com/jeremybanka/wayfarer/blob/main/docs/ci.md) for the workflow and verified runs.

## Registration and maintenance

On the host, with `gh` authenticated and `wayforge` running:

```sh
./vms/projects/wayforge/register-wayfarer-runner.sh
```

This sends only a fresh, short-lived repository registration token into a root-only file at `/var/lib/wayfarer-ci-secrets/registration-token`, then restarts the service. No PAT is stored in the guest or Nix store. Normal restarts reuse runner state. Refresh the token when registration settings change or state is lost; a saved registration token expires after an hour.

Inspect or restart without rebuilding:

```sh
limactl shell wayforge -- systemctl status github-runner-wayfarer
limactl shell wayforge -- sudo journalctl -u github-runner-wayfarer -n 50 --no-pager
limactl shell wayforge -- sudo systemctl restart github-runner-wayfarer
```

When changing the module on an existing guest, sync it into the guest's materialized project shim, build/review the NixOS configuration, then switch. The initial deployment used `/home/jem/scrubs-bootstrap/scrubs#scrubs-base` and did not rebootstrap or reboot the guest. The main scrubs bootstrap also includes this project import for future provisioning.

The NixOS package disables the upstream runner self-updater. Keep its pinned nixpkgs current using the reviewed scrubs update process. If scrubs runtime templates change, refresh the provisioned developer runtime first and restart `wayfarer-ci-home` and the runner to copy the allowlisted runtime into CI.

## OpenRig expedition planning

The [working crew plan](openrig/PLAN.md) describes a VM-owned, cross-repository
OpenRig expedition and its task/worktree lifecycle. It is a design draft, not a
deployed rig or cleanup policy.
