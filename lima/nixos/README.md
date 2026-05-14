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

`bootstrap.sh` no longer depends on `darwin.linux-builder`.

Instead it:

1. boots a generic NixOS image with Lima
2. copies a minimal scrubs payload into the guest
3. runs `nixos-rebuild switch` inside the guest
4. leaves you with a disposable VM that still feels like your environment

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

The current scaffold is pinned to the official NixOS 25.11 minimal ARM ISO
released on April 18, 2026:

- [Release page](https://releases.nixos.org/nixos/25.11/nixos-25.11.9418.c7f47036d3df)
- [Direct ISO URL](https://releases.nixos.org/nixos/25.11/nixos-25.11.9418.c7f47036d3df/nixos-minimal-25.11.9418.c7f47036d3df-aarch64-linux.iso)

To boot the seed installer:

```sh
SCRUBS_SEED_ISO="https://releases.nixos.org/nixos/25.11/nixos-25.11.9418.c7f47036d3df/nixos-minimal-25.11.9418.c7f47036d3df-aarch64-linux.iso" \
./lima/nixos/seed.sh
```

That mounts [`lima/nixos/seed`](/Users/jem/dotfiles/lima/nixos/seed) into the
installer VM at `/mnt/host-scrubs-seed`.

If `~/.lima/scrubs-seed/iso` already exists, `seed.sh` reuses that local
installer artifact instead of downloading the ISO again.

If no ISO is specified, `seed.sh` next looks for a central cache file at:

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
./lima/nixos/export-seed-image.sh scrubs-seed /absolute/path/to/nixos-base-aarch64.qcow2
```

## Configure the Base Image

Copy [`settings.env.example`](./settings.env.example) to `settings.env` and set
your base image path or URL.

```sh
cp ./lima/nixos/settings.env.example ./lima/nixos/settings.env
```

Then edit `settings.env` to point at your generic NixOS image.

## Boot a Guest

```sh
./lima/nixos/bootstrap.sh
```

By default this creates a `scrubs-dev` Lima instance and uses your current macOS
username as the guest username. It also defaults to `aarch64`, so if your base
image is `x86_64` you need to say so explicitly.

You can override those with environment variables:

```sh
SCRUBS_BASE_IMAGE=/absolute/path/to/nixos.qcow2 \
SCRUBS_ARCH=x86_64 \
SCRUBS_GUEST_USER=jem \
SCRUBS_BOOTSTRAP_USER=jem \
./lima/nixos/bootstrap.sh my-project
```

After bootstrap finishes:

- `limactl shell my-project`
- or SSH using the pattern from [`ssh_config.example`](./ssh_config.example)

## Security Defaults

- no host home-directory mount
- no SSH agent forwarding
- no browser or password-manager state in the guest
- no dependency on host-global Nix builder state
- no assumption that the repo itself ships Nix

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
./lima/nixos/bootstrap.sh
```

That failure can come from Lima's generated cloud-init locking the bootstrap
user account. The template includes a cloud-init per-instance script that waits
for the bootstrap user to exist, replaces the locked password with a random
one, and then lets SSH public-key login succeed while password authentication
remains disabled.

## Next Layer

The next step after this base flow is a small per-project extension mechanism,
so a repo can ask for extra packages or helper setup without owning the entire
machine definition.
