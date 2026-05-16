# nixOS on Lima

This directory now models `scrubs` as a reusable personal base environment,
not as a repo-built disk image.

The intended layering is:

- macOS is the trusted thin client
- a generic NixOS image is the disposable substrate
- `scrubs-base` is your personal CLI home inside that substrate
- project-specific tweaks can be layered on top later

## What Gets Applied

`scrubs-base` currently converges the guest onto:

- your `git` config
- your `nushell` config
- your `mise` config
- `git`, `nushell`, `mise`, `bun`, and common CLI utilities
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

That mounts [`lima/nixos/seed`](/Users/jem/dotfiles/lima/nixos/seed) into the
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

Copy [`settings.env.example`](./settings.env.example) to `settings.env` and set
your base image path or URL.

```sh
cp ./lima/nixos/settings.env.example ./lima/nixos/settings.env
```

Then edit `settings.env` to point at your generic NixOS image.

The default local convention for active base images is:

- [`lima/nixos/qcow2`](/Users/jem/dotfiles/lima/nixos/qcow2) for living local images
- `~/Library/Mobile Documents/com~apple~CloudDocs/scrubs/base-images/` for the iCloud mirror

The helper scripts are:

```sh
just sync-base-image-to-icloud
just sync-base-image-from-icloud
```

Both overwrite by name on the destination side. The intended pattern is:

1. export or refresh locally into `lima/nixos/qcow2/`
2. validate the image locally
3. mirror it to iCloud by name

If you want to specify a different image name:

```sh
just sync-base-image-to-icloud scrubs-linux-lts.qcow2
just sync-base-image-from-icloud scrubs-linux-lts.qcow2
```

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

To pick up those fixes:

1. bump the `scrubs` flake inputs or guest configuration in this repo
2. build a refreshed base image with `just refresh-base-image`
3. recreate project guests from the refreshed image, or run `nixos-rebuild`
   inside any long-lived guest you want to patch in place

So: no, the guests do not have to be frozen in time, but updates are explicit
and artifact-driven rather than background-managed.

## Asset Retention

The repo should carry provenance for important binary assets without becoming
the binary store itself.

- seed ISO: rely on NixOS as the canonical host, keep a local cache, and record
  source URL plus checksum metadata
- base qcow2: keep the living copy in `lima/nixos/qcow2/`, keep it out of Git,
  and mirror it to iCloud by name because it contains manual setup value

The fuller policy lives in [ASSET-RETENTION.md](/Users/jem/dotfiles/lima/nixos/ASSET-RETENTION.md).

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
`export-seed-image.nu` clears cloud-init instance state before conversion so
fresh clones reprocess Lima's NoCloud `cidata` on first boot.

## Next Layer

The next step after this base flow is a small per-project extension mechanism,
so a repo can ask for extra packages or helper setup without owning the entire
machine definition.
