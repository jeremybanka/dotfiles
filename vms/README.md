# Scrubs

This directory models `scrubs` as a reusable personal base environment on top
of Lima and NixOS, not as a repo-built disk image.

The intended layering is:

- macOS is the trusted thin client
- a generic NixOS image is the disposable substrate
- `scrubs-base` is your personal CLI home inside that substrate
- project-specific tweaks can be layered on top later

## Mission

Scrubs is a macOS developer's last line of defense.

Stowaway malware programs in the package ecosystems we use every day, such as
`npm`, `jsr`, and `cargo`, should not reach our development machines, but they
want to, and it is safer to assume that the smartest among them eventually
will. When that happens, the goal is not to pretend the risk never existed.
The goal is to keep the blast radius small.

Scrubs exists to make that outcome practical: a convenient local developer
environment, running at native speed, without handing ambient secrets to every
tool you try. The working hope is simple: if hostile dependency code lands in
your workflow, it should not get far.

## Security Posture

Scrubs is a boundary-hardening tool, not a perfect isolation story.

Its current strong path is:

- macOS remains the trusted thin client
- clean-space credentials are host-sourced and sealed at rest in the guest
- dirty package-manager workloads are pushed through an explicit sandboxed path
- ordinary developer workflows stay convenient enough to be the default

The current design is intentionally aimed at "stowaway malware in ordinary
developer tooling should not reach very far," not at "a fully compromised guest
account or guest root should still be unable to recover secrets."

## Caveats

Scrubs inherits meaningful trust and maintenance assumptions from the guest OS
and package base it stands on.

The important caveats today are:

- scrubs inherits the security weaknesses of NixOS and the pace of the pinned
  `nixpkgs` inputs it depends on
- urgent upstream security fixes may not land on the cadence you would expect
  from a faster-moving distro or package channel
- the Nix store is clean space; binaries and libraries you install from it are
  treated as trusted code in this model
- the current sealed-secret design is strong against the dirty-runtime
  boundary, but it is not meant to survive a full clean-guest compromise

## Why This Shape

We explored two broad approaches:

1. host-built NixOS images via `darwin.linux-builder`
2. a generic bootable NixOS seed image plus first-boot convergence inside Lima

The host-built path was abandoned because it depended on host-global privileged
Nix setup and behaved like pet infrastructure.

The current model uses:

- one reusable seeded base image
- disposable per-project Lima guests cloned from that base
- a shared `scrubs` guest config applied inside the guest

On Apple Silicon, Lima's `vz` backend is the practical default. In local
testing it removed the heavy idle CPU overhead we saw under `qemu` while
keeping the VM isolation model intact.

## What Gets Applied

`scrubs-base` currently converges the guest onto:

- your `git` config
- your `nushell` config
- your `mise` config
- clean shells that stay Nix-first while `mise`-backed tools are proxied through the scrubs dirty-runtime launcher
- optional sealed clean-auth wrappers for `gh` and `codex` when host secrets are configured
- a writable `mise` cache under `/tmp` so sandboxed commands stay quiet
- `git`, `nushell`, `mise`, `bun`, `codex`, and common CLI utilities
- hardened SSH defaults inside the guest

It does not assume the cloned project owns a flake.

## Bootstrap Model

`bootstrap.nu` no longer depends on `darwin.linux-builder`.

Instead it:

1. boots a generic NixOS image with Lima
2. copies a minimal scrubs payload into the guest
3. runs `nixos-rebuild switch` inside the guest
4. leaves you with a disposable VM that still feels like your environment

On Apple Silicon macOS, the scrubs runtime path now defaults to Lima's `vz`
backend rather than `qemu`. In local testing, `vz` reduced hot-idle host CPU
from hundreds of percent under `qemu` to effectively idle.

## Current Status

What is working well today:

- reusable `aarch64` NixOS guests on Lima
- SSH bootstrap into fresh cloned guests
- Lima guest agent support
- shared `git`, `nushell`, `mise`, and common CLI setup inside the guest
- efficient runtime behavior on `vz`

What is still rough:

- JavaScript runtime management is not yet especially elegant on NixOS guests
- some repos may still want a more Nix-native runtime path than pure `mise`
- a few SSH/bootstrap compatibility workarounds are still intentionally present

## Requirements

- `lima` installed on macOS
- an OpenStack-compatible NixOS base image with cloud-init support
- a guest image that allows the bootstrap user to `sudo` without interaction

Lima’s own guest requirements are important here: for a Linux image to work
well, it needs `cloud-init`, `sudo`, and a few supporting tools preinstalled.
Source: [Lima FAQ](https://lima-vm.io/docs/faq/).

## Create a Native ARM Seed Image

If you do not already have an `aarch64` NixOS base image, create one once from
the official NixOS ARM installer ISO.

This installer path is best treated as a factory-bootstrap or disaster-recovery
flow, not as the normal way to pick up routine security updates.

The current scaffold is pinned to the official NixOS 25.11 minimal ARM ISO
released on April 18, 2026:

- [Release page](https://releases.nixos.org/nixos/25.11/nixos-25.11.9418.c7f47036d3df)
- [Direct ISO URL](https://releases.nixos.org/nixos/25.11/nixos-25.11.9418.c7f47036d3df/nixos-minimal-25.11.9418.c7f47036d3df-aarch64-linux.iso)

If you want a convenience fetch for the latest stable ARM minimal installer
instead of manually hunting the URL each time, use:

```sh
just download-latest-iso
```

That downloads from the `nixos-25.11` channel by default and stores the ISO in
`~/Library/Caches/scrubs` together with a resolved release URL file and a local
SHA-256 sidecar.

To boot the seed installer:

```sh
SCRUBS_SEED_ISO="https://releases.nixos.org/nixos/25.11/nixos-25.11.9418.c7f47036d3df/nixos-minimal-25.11.9418.c7f47036d3df-aarch64-linux.iso" \
just seed
```

The installer flow intentionally still uses `qemu` plus a repo mount so you can
run the seed helper scripts from the live ISO. The reusable scrubs guest you
boot afterward defaults to `vz`.

That mounts [`vms/seed`](/Users/jem/dotfiles/vms/seed) into the
installer VM at `/mnt/host-scrubs-seed`.

If `~/.lima/scrubs-seed/iso` already exists, `just seed` reuses that local
installer artifact instead of downloading the ISO again.

If no ISO is specified, `just seed` next looks for a central cache file at:

```sh
~/Library/Caches/scrubs/nixos-minimal-aarch64.iso
```

It also normalizes `~`, `$HOME/...`, and `${HOME}/...` if those are passed in
`SCRUBS_SEED_ISO`.

Inside the installer console, run:

```sh
sudo -i
/mnt/host-scrubs-seed/install.sh
```

After installation finishes, shut the guest down and export the reusable base
image:

```sh
just export-seed-image scrubs-seed /absolute/path/to/nixos-base-aarch64.qcow2
```

## Refresh an Existing Base Image

Once you already have a working base image, routine Linux and NixOS updates do
not need a fresh trip through the live installer.

Instead:

1. update the pinned `scrubs` Nix inputs or guest modules in this repo
2. boot the existing base image as a normal disposable `scrubs` guest
3. apply the current flake inside that guest
4. export the refreshed disk as a new qcow2

The helper script for that flow is:

```sh
just refresh-base-image \
  /absolute/path/to/current-base.qcow2 \
  /absolute/path/to/refreshed-base.qcow2
```

By default this uses `SCRUBS_REFRESH_VM_TYPE=vz`, because this is just a normal
native-arch Linux guest boot and does not depend on the live ISO path.

If you want to keep the temporary maintenance VM around after export for
inspection, set:

```sh
SCRUBS_REFRESH_DELETE_INSTANCE=false \
just refresh-base-image \
  /absolute/path/to/current-base.qcow2 \
  /absolute/path/to/refreshed-base.qcow2
```

## Configure the Base Image

Copy [`settings.env.example`](./settings.env.example) to `vms/settings.env` and
set your base image path or URL.

```sh
cp ./vms/settings.env.example ./vms/settings.env
```

Then edit `vms/settings.env` to point at your generic NixOS image.

If you want bootstrap to pre-provision clean-space auth for `gh`, `codex`, or
guest-side Tailscale, you can point scrubs at host-side secret sources:

```sh
SCRUBS_GH_TOKEN_KEYCHAIN_SERVICE__PERSONAL=scrubs-gh-token-personal
SCRUBS_GH_TOKEN_KEYCHAIN_ACCOUNT__PERSONAL=github.com
SCRUBS_TAILSCALE_OAUTH_SECRET_KEYCHAIN_SERVICE=scrubs-tailscale-oauth-secret
SCRUBS_TAILSCALE_OAUTH_SECRET_KEYCHAIN_ACCOUNT=tailscale
SCRUBS_TAILSCALE_TAGS=tag:scrubs
SCRUBS_CODEX_AUTH_JSON_PATH=~/.codex/auth.json
```

For GitHub, a direct `SCRUBS_GH_TOKEN` value is also supported, but the
intended strong path is host-password-manager sourcing. For Codex, the strong
path is the host ChatGPT login bundle from `~/.codex/auth.json` or an explicit
`SCRUBS_CODEX_AUTH_JSON_PATH`; scrubs does not use API-key auth for Codex in
the guest path. For Tailscale, the intended host input is an OAuth client
secret with the `auth_keys` scope stored in the macOS Keychain as one global
scrubs secret. When
configured, bootstrap seals guest-local auth artifacts and installs the clean
runtime needed to use them. `gh` and `codex` materialize their credentials on
demand for the target process. Tailscale materializes its OAuth client secret
into `/run` long enough for the NixOS `tailscaled-autoconnect` path to bring
the guest up as a tagged node, then clears the plaintext secret from `/run`.
When sealed GitHub auth is present,
scrubs also writes the Git credential helper configuration for
`https://github.com` and `https://gist.github.com` so ordinary HTTPS Git
operations flow through the scrubs `gh` wrapper rather than depending on
`gh auth setup-git`.

If you need multiple host-side clean auth contexts, scrubs now supports a
selected clean auth profile at bootstrap time. The model is:

- keep the simple single-profile path on the unsuffixed setting names
- default the selected profile to `personal`
- optionally pick a different profile with `SCRUBS_CLEAN_AUTH_PROFILE=<name>`
  or `just bootstrap <instance> <profile>`
- leave Tailscale enabled by default, or append `tailscale-disabled` as the
  final bootstrap argument for disposable test guests that should stay off the
  tailnet
- define profile-specific overrides by appending `__<PROFILE>` to the base
  setting name for settings that actually vary by profile, where `<PROFILE>` is
  the uppercased profile label with non-alphanumeric runs converted to `_`
- keep Tailscale global across profiles on the unsuffixed settings and Keychain
  service

For example, a personal/work GitHub split can look like:

```sh
SCRUBS_CLEAN_AUTH_PROFILE=personal
SCRUBS_GH_TOKEN_KEYCHAIN_SERVICE__PERSONAL=scrubs-gh-token-personal
SCRUBS_GH_TOKEN_KEYCHAIN_ACCOUNT__PERSONAL=github.com
SCRUBS_GH_TOKEN_KEYCHAIN_SERVICE__WORK=scrubs-gh-token-work
SCRUBS_GH_TOKEN_KEYCHAIN_ACCOUNT__WORK=github.com
SCRUBS_TAILSCALE_OAUTH_SECRET_KEYCHAIN_SERVICE=scrubs-tailscale-oauth-secret
SCRUBS_TAILSCALE_OAUTH_SECRET_KEYCHAIN_ACCOUNT=tailscale
SCRUBS_TAILSCALE_TAGS=tag:scrubs
SCRUBS_TAILSCALE_PREAUTHORIZED=true
SCRUBS_TAILSCALE_EPHEMERAL=false
SCRUBS_CODEX_AUTH_JSON_PATH=~/.codex/auth.json
```

That keeps one shared Tailscale secret and one shared Codex bundle on the
unsuffixed keys while letting GitHub switch cleanly between personal and work
tokens. The same suffixing model can be used for other truly profile-specific
clean-auth settings later.

The intended host-side flow is:

```sh
just scrubs-auth-set-gh
just scrubs-auth-set-gh work
just scrubs-auth-set-tailscale
codex login
just scrubs-auth-status
```

With no profile argument, `just scrubs-auth-status` reports `personal` and
`work` by default, then adds any extra GitHub auth profiles it can discover
from `vms/settings.env`. You can still narrow it to one profile with
`just scrubs-auth-status work`. The status command reports one global
Tailscale secret line and also checks the legacy `scrubs-tailscale-auth-key`
entry plus older `personal`-scoped Tailscale entries during migration.

GitHub uses the macOS Keychain entry:

- service `scrubs-gh-token-personal`, account `github.com` for the default
  `personal` profile
- service `scrubs-gh-token-work`, account `github.com` for a `work` profile

Tailscale uses the macOS Keychain entry:

- service `scrubs-tailscale-oauth-secret`, account `tailscale`

Codex uses the host ChatGPT auth bundle at:

- `SCRUBS_CODEX_AUTH_JSON_PATH` if set
- otherwise `~/.codex/auth.json`

The helper recipes keep the GitHub account label fixed at `github.com`, so the
only knob you normally need is the profile name. The Tailscale helper recipes
keep the account label fixed at `tailscale` and use one shared host secret;
use an OAuth client secret with the `auth_keys` scope and a server tag such as
`tag:scrubs`. For Codex, make sure the host auth bundle exists by logging in
on the host first.

For multiple GitHub profiles, the helper recipes derive the service name from
the profile so the CLI shape matches bootstrap:

```sh
just scrubs-auth-set-gh personal
just scrubs-auth-set-gh work
just scrubs-auth-set-tailscale
just scrubs-auth-status
just scrubs-auth-status work
just scrubs-auth-delete-gh personal
just scrubs-auth-delete-tailscale
```

Bootstrap selection precedence is:

1. `--clean-auth-profile` or `just bootstrap <instance> <profile>` on the
   current bootstrap command
2. `SCRUBS_CLEAN_AUTH_PROFILE` from the environment or `vms/settings.env`
3. the built-in default profile name `personal`

So the common paths are:

```sh
just bootstrap scrubs-dev
just bootstrap sec-lab work
just bootstrap sec-lab work security-testing /absolute/path/to/nixos.qcow2
just bootstrap sec-lab work security-testing /absolute/path/to/nixos.qcow2 tailscale-disabled
```

For rotation or cleanup:

```sh
just scrubs-auth-delete-gh
just scrubs-auth-delete-tailscale
just scrubs-auth-delete-codex
```

`just scrubs-auth-delete-codex` is advisory and reminds you to run
`codex logout` on the host, because the host-side ChatGPT login bundle is the
source of truth.

Within the guest, scrubs now treats Codex state in two classes:

- durable guest-local Codex state lives in `~/.codex/`, including chat and
  session history such as `history.jsonl`, `session_index.jsonl`, `sessions/`,
  and the local SQLite state files
- ephemeral clean auth lives only in the tmpfs runtime file materialized by the
  scrubs wrapper, with `~/.codex/auth.json` maintained as a symlink to that
  runtime file while Codex is launched through the clean wrapper

This preserves guest-local conversation state across `just bootstrap
<instance>` while keeping the ChatGPT auth bundle out of the durable guest
Codex home. Existing guests using the older tmpfs-backed `CODEX_HOME` layout
are migrated automatically the next time the scrubs `codex` wrapper launches:
the wrapper copies forward non-secret state from the legacy runtime home into
the durable `~/.codex` directory and continues to source auth from the sealed
runtime path.

## Direct Mobile Access

If a Tailscale OAuth client secret is configured for the selected clean auth
profile,
bootstrap now enables guest-side Tailscale from NixOS on every guest. The
recommended path is to create an OAuth client with the `auth_keys` scope and a
guest tag such as `tag:scrubs`, then store that OAuth client secret on the
host with `just scrubs-auth-set-tailscale`. The guest keeps its existing
Lima-local SSH path for host workflows, but it also joins your tailnet
automatically on first boot as a tagged node and enables Tailscale SSH.

The node name is derived from the Lima instance name, so a guest bootstrapped
as `wayforge` will register a Tailscale hostname derived from `wayforge`.
Scrubs also sets `--accept-dns=false` on the guest Tailscale client so the
tailnet does not silently replace the guest's existing DNS defaults. By
default, scrubs requests `preauthorized=true` and `ephemeral=false`; if your
tailnet policy wants different behavior, override
`SCRUBS_TAILSCALE_PREAUTHORIZED` or `SCRUBS_TAILSCALE_EPHEMERAL`.
If you are bootstrapping a disposable test guest and do not want tailnet
enrollment at all, append `tailscale-disabled` as the final `just bootstrap`
argument for that run.

The intended setup flow is:

1. create or choose a guest tag such as `tag:scrubs` in your tailnet policy
2. create a Tailscale OAuth client with the `auth_keys` scope for that tag
3. store the OAuth client secret on the host with `just scrubs-auth-set-tailscale`
4. bootstrap or re-bootstrap the guest with `just bootstrap <instance>`
5. confirm the guest joined the tailnet with `limactl shell <instance> -- tailscale status`
6. connect from your phone over Tailscale SSH using the guest's tailnet name

For the exact click-by-click walkthrough, including the current Tailscale UI
labels (`Description`, `Keys -> Auth Keys -> Write`) and the common
troubleshooting path for a guest that initially shows `Logged out.`, use
[tailscale-direct-guest-access.md](/Users/jem/dotfiles/vms/docs/tailscale-direct-guest-access.md).

Some mobile SSH clients do not accept Tailscale SSH's no-auth flow directly.
When that happens, use the username suffix `+password` and enter any password.
That compatibility path does not require enabling a real guest password.

A minimal policy shape for tagged scrubs guests looks like:

```json
{
  "tagOwners": {
    "tag:scrubs": ["you@example.com"]
  },
  "grants": [
    {
      "src": ["user:you@example.com"],
      "dst": ["tag:scrubs"],
      "ip": ["*"]
    }
  ],
  "ssh": [
    {
      "action": "accept",
      "src": ["user:you@example.com"],
      "dst": ["tag:scrubs"],
      "users": ["jem"]
    }
  ]
}
```

Prefer explicit host usernames such as `jem` on tagged guests instead of
`autogroup:nonroot`, because Tailscale SSH treats `autogroup:nonroot` broadly
once the destination is no longer `autogroup:self`.

The default local convention for active base images is:

- [`vms/images`](/Users/jem/dotfiles/vms/images) for living local images
- `~/Library/Mobile Documents/com~apple~CloudDocs/scrubs/base-images/` for the iCloud mirror

The helper scripts are:

```sh
just sync-base-image-to-icloud
just sync-base-image-from-icloud
```

Both overwrite by name on the destination side. The intended pattern is:

1. export or refresh locally into `vms/images/`
2. validate the image locally
3. mirror it to iCloud by name

If you want to specify a different image name:

```sh
just sync-base-image-to-icloud scrubs.qcow2
just sync-base-image-from-icloud scrubs.qcow2
```

## Asset Retention

The repo should carry provenance for important binary assets without becoming
the binary store itself.

Retention principles:

- keep provenance in Git
- keep large binaries out of Git
- prefer reproducible upstream inputs where possible
- back up manually produced artifacts at least twice

For the seed ISO:

- treat NixOS release infrastructure as the canonical source
- keep only a local convenience cache in `~/Library/Caches/scrubs`
- keep resolved release URL and SHA-256 sidecars, not the ISO itself, in mind
  as the provenance story

`just download-latest-iso` writes the ISO plus `*.source-url` and `*.sha256`
sidecars into the local cache so the seed input is understandable without
committing a large installer artifact into the repo.

For the base qcow2:

- do not commit it to Git
- do not treat Git LFS as the primary storage plan
- keep one active local copy in [`vms/images`](/Users/jem/dotfiles/vms/images)
- keep at least one mirrored backup outside the repo

The default storage model is:

- working copy in [`vms/images`](/Users/jem/dotfiles/vms/images)
- named mirror in `~/Library/Mobile Documents/com~apple~CloudDocs/scrubs/base-images/`
- optional second backup in any durable store you already trust

Good file naming keeps the artifact story append-only and rollback-friendly:

```text
nixos-base-aarch64-2026-05-15.qcow2
nixos-base-aarch64-2026-05-15-kernel7.qcow2
```

If the seed ISO is lost, redownload it and recompute the checksum. If the
working base qcow2 is lost, restore it from backup or rebuild it from the seed
path in this repo.

## Boot a Guest

```sh
just bootstrap /absolute/path/to/nixos.qcow2
```

By default this creates a `scrubs-dev` Lima instance and uses your current macOS
username as the guest username. It defaults to `SCRUBS_VM_TYPE=vz` and
`SCRUBS_ARCH=aarch64`, so if your base image is `x86_64` you need to say so
explicitly.

You can override those with environment variables:

```sh
SCRUBS_VM_TYPE=qemu \
SCRUBS_ARCH=x86_64 \
SCRUBS_GUEST_USER=jem \
SCRUBS_BOOTSTRAP_USER=jem \
just bootstrap /absolute/path/to/nixos.qcow2 my-project
```

After bootstrap finishes:

- `limactl shell my-project`
- or `just vm-shell my-project`
- or SSH using the pattern from [`ssh_config.example`](./ssh_config.example)
- or, when Tailscale auth is configured, Tailscale SSH to the guest's tailnet
  hostname from another device

The guest keeps a POSIX login shell for compatibility with Lima and bootstrap
tools. `nu` is still installed; start it manually after login when you want it.

## Security Defaults

- no host home-directory mount
- no SSH agent forwarding
- no browser or password-manager state in the guest
- no dependency on host-global Nix builder state
- no assumption that the repo itself ships Nix

## Patch Model

`scrubs` guests are intentionally not self-updating pets.

The practical model is:

- the base image is a versioned artifact you refresh on purpose
- per-project guests are snapshots of that artifact plus repo-specific work
- running guests stay where they are until you explicitly rebuild or recreate
  them

That means critical Linux or NixOS fixes are not applied automatically just
because upstream published them.

Host-side Lima template fixes are a little different: `just bootstrap
<instance>` now refreshes the instance's
`~/.lima/<instance>/lima.yaml` from the current scrubs template before it
starts an existing guest. That lets compatibility fixes in the Lima-side
bootstrapping flow roll forward without deleting and recreating the guest.

To pick up those fixes:

1. bump the `scrubs` flake inputs or guest configuration in this repo
2. build a refreshed base image with `just refresh-base-image`
3. recreate project guests from the refreshed image, or run `nixos-rebuild`
   inside any long-lived guest you want to patch in place

So: no, the guests do not have to be frozen in time, but updates are explicit
and artifact-driven rather than background-managed.

## Bootstrap Caveats

The current bootstrap path still intentionally carries a few compatibility
choices that are worth preserving until a fresh seed image proves they are no
longer needed.

Keep for now:

- `services.cloud-init.enable = true` in [modules/clean-base.nix](/Users/jem/dotfiles/vms/modules/clean-base.nix)
- `services.envfs.enable` plus the `/bin/bash` fallback in [seed/base.nix](/Users/jem/dotfiles/vms/seed/base.nix)
- `user.shell = "/bin/sh"` in [lima.yaml](/Users/jem/dotfiles/vms/lima.yaml)
- the `mode: boot` unlock provision in [lima.yaml](/Users/jem/dotfiles/vms/lima.yaml)

Do not reintroduce:

- old `services.cloud-init.config` module-list overrides in [seed/base.nix](/Users/jem/dotfiles/vms/seed/base.nix)

Those overrides accidentally disabled Lima's `bootcmd`, which blocked the
pre-SSH unlock path entirely.

Once a fresh seed image gives one clean `just bootstrap` run, the cleanup order
should be:

1. confirm SSH, payload copy, and `nixos-rebuild` are all stable
2. decide whether to keep Lima-created users or move to `user: false`
3. remove the unlock-script workaround if the seed owns the bootstrap user
4. reassess `UsePAM = false` in [seed/base.nix](/Users/jem/dotfiles/vms/seed/base.nix)

## Validation Baseline

The default validation pass for scrubs guest changes should now be treated as
a small regression plan rather than a single idempotence smoke check.

The core questions are:

1. can a fresh guest bootstrap cleanly
2. can the same guest survive a repeat bootstrap without losing operator access
3. do clean-space auth paths still work without interactive login ceremony
4. does dirty space remain unable to discover or invoke the clean auth surface
5. does ordinary HTTPS Git still work through the scrubs-owned `gh` helper path

The intended operator process for future feature work is:

1. treat the standard test guest as disposable and local-first
2. prefer the existing Lima-local access paths such as `limactl shell <instance>`
   and the host-local SSH bootstrap path during ordinary regression testing
3. do not provision guest-side Tailscale as part of the default testing
   procedure unless Tailscale behavior is itself part of what is being tested
4. when a feature does need Tailscale coverage, treat that as an explicit
   additional validation track rather than the baseline every feature must run

This keeps short-lived test guests from accumulating stale tailnet nodes and
helps preserve a clear distinction between the ordinary scrubs regression path
and tests that intentionally exercise direct tailnet enrollment.

For any new or materially changed guest flow, the baseline pass is:

1. create a fresh throwaway guest
2. confirm `limactl shell <instance>` opens an interactive shell
3. confirm clean-space `gh` and Codex auth are usable without interactive login
4. create a simple Codex continuity marker, for example with `codex exec`, and
   confirm the resulting guest-local session or history artifact appears under
   `~/.codex`
5. confirm dirty-space probes cannot discover `clean-auth`, `gh`, or `codex`
6. confirm `git credential fill` succeeds for `github.com` through the scrubs helper path
7. confirm an HTTPS read operation such as `git ls-remote` succeeds
8. confirm a non-destructive push-shaped probe such as `git push --dry-run` succeeds when the configured token should allow it
9. run `just bootstrap <instance>` again on that same guest
10. confirm `limactl shell <instance>` still opens an interactive shell
11. confirm the prior Codex continuity marker is still present in the durable
    `~/.codex` state after re-bootstrap

Add the following only when the specific feature or regression under test
depends on guest-side Tailscale:

1. bootstrap the guest through the explicit Tailscale-enabled path for that test
2. confirm `tailscale status` reports the guest as running
3. confirm `tailscale set --ssh` state is active if Tailscale SSH is part of
   the intended behavior
4. clean up the tailnet node afterward if the test intentionally created a
   disposable enrolled guest

This does not replace workload-specific validation, but it is the default
guardrail for scrubs changes. A guest that cannot survive re-bootstrap without
locking out `limactl shell`, or that silently regresses its clean auth or Git
boundaries, is not healthy enough to treat as upgradable in place.

GitHub-hosted Actions can cover only part of this plan. The real Apple
Silicon `vz` path should be treated as a local or self-hosted Apple Silicon
runner concern, because GitHub-hosted macOS arm64 runners do not support the
nested virtualization story needed for the full scrubs runtime path.

## Troubleshooting

If Lima stalls before SSH comes up, check the serial log:

```sh
tail -n 120 ~/.lima/scrubs-dev/serial.log
```

If you see `Image type X64 can't be loaded on AARCH64 UEFI system`, your base
image architecture and `SCRUBS_ARCH` do not match. Use an `aarch64` image or set
`SCRUBS_ARCH=x86_64`.

If the guest boots but Lima keeps reporting `Permission denied (publickey)`,
delete and recreate the instance after updating the template metadata:

```sh
limactl delete scrubs-dev
just bootstrap /absolute/path/to/nixos.qcow2
```

That failure can come from Lima's generated cloud-init locking the bootstrap
user account. The template includes a cloud-init per-instance script that waits
for the bootstrap user to exist, replaces the locked password with a random
one, and then lets SSH public-key login succeed while password authentication
remains disabled.

If SSH comes up but `limactl start` still stalls on readiness checks like
`/mnt/lima-cidata/param.env` or `/run/lima-ssh-ready`, the exported base image
probably lost `cloud-init` support or carried stale cloud-init instance state.
The `scrubs-base` guest config now keeps `cloud-init` enabled, and
`export-seed-image.nu` now runs Nix garbage collection, clears cloud-init
instance state, and trims free space before conversion so fresh clones
reprocess Lima's NoCloud `cidata` on first boot without carrying unnecessary
store bloat into the exported image.

## Notes

[SEED-INSTALL-CHECKLIST.md](/Users/jem/dotfiles/vms/docs/SEED-INSTALL-CHECKLIST.md)
is the exact manual runbook for the live installer path. Treat this README as
the canonical operator guide and the checklist as the precise recovery or
factory-bootstrap procedure.

## Next Layer

The next step after this base flow is a small per-project extension mechanism,
so a repo can ask for extra packages or helper setup without owning the entire
machine definition.

That now exists as a small per-project shim directory, with an optional
shim-name override:

- if [`vms/projects`](/Users/jem/dotfiles/vms/projects) contains a directory
  named `<instance-name>`, `just bootstrap ... <instance-name>` uses that
  directory as the shim bundle
- if you want a public, non-project-specific shim name, pass
  `shim_name=<shim-name>` to `just bootstrap` or `--shim-name <shim-name>` to
  [`bootstrap.nu`](/Users/jem/dotfiles/vms/bootstrap.nu); that resolves
  `vms/projects/<shim-name>/` instead
- `guest.nix` is copied into the guest payload as `modules/project-shim.nix`
- optional `lima.yaml` currently supports a `portForwards` list that gets
  appended to the generated Lima `portForwards` list for that VM only
- optional `sandbox-policy.nuon` is now the preferred dirty-space sandbox
  override; it replaces the guest-wide policy artifact for helper commands,
  copied files, mounted system facts, writable directories, and proc handling
- scrubs renders that `.nuon` policy into `sandbox-definition.sh` inside the
  guest so the current shell launcher can keep consuming a stable generated
  artifact
- legacy `sandbox-definition.sh` overrides still work for project shims that
  have not been ported yet; those can continue sourcing the base artifact at
  `~/.local/libexec/scrubs/sandbox-default-definition.sh`

This keeps project-specific accommodations in version control without baking
them into the reusable base image.

One ready-made shim is [`security-testing`](/Users/jem/dotfiles/vms/projects/security-testing).
It bootstraps:

- `linpeas`
- `trufflehog`
- Atomic Red Team under `/opt/security/atomic-red-team`

Bootstrap a fresh lab VM with it like this:

```sh
just bootstrap sec-lab security-testing /absolute/path/to/nixos.qcow2
```

Or explicitly by shim name if you want a different instance name:

```sh
just bootstrap sec-lab shim_name=security-testing source_image=/absolute/path/to/nixos.qcow2
```

To keep a disposable test guest off Tailscale while still using the standard
bootstrap flow, append `tailscale-disabled` as the last argument:

```sh
just bootstrap sec-lab work security-testing /absolute/path/to/nixos.qcow2 tailscale-disabled
```

Inside the guest:

- run `linpeas`
- run `trufflehog`
- run `atomic-red-team` to print the repo path or `atomic-red-team ls atomics`
- inspect tests with `atomic-red-team-path`
- refresh the downloaded tool payloads with `atomic-red-team-update`
