# Scrubs Asset Retention

This project has two important binary assets that should be treated
deliberately, but should generally not live in Git:

- the upstream NixOS installer ISO used to seed a base image
- the manually produced base VM image that carries real setup effort

## Retention Principles

- keep provenance in Git
- keep large binaries out of Git
- prefer reproducible upstream inputs where possible
- back up manually produced artifacts at least twice

## 1. Seed ISO

The seed ISO is an upstream artifact, not a unique local creation.

That means the retention policy can be light:

- canonical source: NixOS release infrastructure
- local role: cache for convenience
- Git role: track how we obtained it, not the binary itself

Recommended workflow:

1. fetch the latest stable ARM installer ISO into a local cache
2. record the resolved release URL and local SHA-256 next to the cache file
3. point `SCRUBS_SEED_ISO` at that cached file or at the resolved upstream URL

Helper:

```sh
just download-latest-iso
```

By default this downloads:

- channel: `nixos-25.11`
- architecture: `aarch64`
- flavor: `minimal`
- cache dir: `~/Library/Caches/scrubs`

It also writes:

- `*.source-url`
- `*.sha256`

Those sidecars give us enough provenance to understand what seeded a base
image without committing a 1 GB+ installer into the repo.

## 2. Base VM Image

The base VM image is different. It contains manual effort and therefore should
be treated like a first-class artifact.

Recommended policy:

- do not commit the qcow2 into Git
- do not rely on Git LFS for the primary copy
- keep one working local copy
- keep at least one backup copy outside the repo
- keep a small manifest in Git if we want a paper trail

Suggested storage model:

- working copy:
  [`lima/nixos/qcow2`](/Users/jem/dotfiles/lima/nixos/qcow2)
- synced backup copy:
  `~/Library/Mobile Documents/com~apple~CloudDocs/scrubs/base-images/`
- optional second backup copy:
  external disk, NAS, Backblaze, S3-compatible object storage, or another
  durable store you already trust

Good file naming helps a lot:

```text
nixos-base-aarch64-2026-05-15.qcow2
nixos-base-aarch64-2026-05-15-kernel7.qcow2
```

That keeps the story append-only and makes rollback easy.

The repo-local `qcow2/` directory is for living base images you actively point
`SCRUBS_BASE_IMAGE` at. The directory is intentionally present in Git, but its
contents are ignored. iCloud is the named mirror for safe retention, not the
primary write target for long-running exports.

The preferred sync entrypoints are:

```sh
just sync-base-image-to-icloud
just sync-base-image-from-icloud
```

## 3. What Git Should Carry

Git should carry:

- scripts
- configuration
- documentation
- resolved URLs
- checksums
- notes about why an image was produced

Git should not carry:

- ISO binaries
- qcow2 base images
- per-project VM disks

## 4. Practical Recovery Story

If the local cache is lost:

- redownload the seed ISO from NixOS
- verify the resolved URL and local checksum again

If the working base qcow2 is lost:

- restore from backup if available
- otherwise rebuild from the seed ISO and repo instructions

That makes the seed ISO recoverable and the base image protected without
turning this repository into a binary warehouse.
