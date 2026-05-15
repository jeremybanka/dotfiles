# Virtualization Scrubs Report

## Goal

Build a disposable per-repo development environment model where:

- macOS stays the thin GUI and identity host
- NixOS-on-Lima is the isolated non-GUI dev environment
- projects are cloned and worked on inside the guest
- personal CLI ergonomics like `git`, `nushell`, `mise`, and `bun` follow us into the guest

## What We Tried

We explored two broad approaches:

1. Host-built NixOS images via `darwin.linux-builder`
2. Generic bootable NixOS seed image plus first-boot convergence inside Lima

We abandoned the first approach because it depended on host-global privileged Nix setup and behaved like pet infrastructure, not cattle.

We then built the second approach:

- seed a reusable `aarch64` NixOS base image
- boot per-instance Lima guests from that image
- apply a shared `scrubs` NixOS configuration inside the guest
- layer repo-specific work on top of that

## What Worked

The following pieces are now working:

- Lima can boot a reusable `aarch64` NixOS guest on Apple Silicon
- guest SSH bootstrap works
- Lima guest agent works
- the `vz` backend works well as the runtime substrate on Apple Silicon
- per-repo instances work
- the guest can carry shared scrubs tooling and dotfiles
- real repos can be cloned and used inside isolated guests
- Nushell startup issues across macOS and NixOS were debugged and mostly stabilized

In practical terms, we successfully got to:

- a running `scrubs-dev`
- a separate `scrubs-wayforge`
- `jeremybanka/wayforge` cloned inside the guest
- `git`, `nu`, `mise`, and `bun` available in the guest
- a fresh `scrubs-dev` booted on `vz` with working SSH, working guest agent,
  and working Nushell

## Major Obstacles

Two major blockers emerged, but one of them now has a good answer.

### 1. Runtime/tooling mismatch on NixOS

Many modern JS tools assume generic dynamically linked Linux environments.

We had to add compatibility and baseline tooling such as:

- `nix-ld`
- `python`
- `gnupg`
- compiler/build tooling

Even after that, `mise` resolving `node` through its `core:node` backend led to a source build of Node.js inside the VM.

Current observed impact:

- Node compilation has run for hours
- this is too slow and too heavy for a disposable per-repo workflow
- exact-version JS runtime management via `mise` is not yet a good fit for this guest model

### 2. QEMU VM overhead on Apple Silicon

The original `qemu` runtime path imposed much more background cost than expected.

Observed impact under `qemu`:

- the VM keeps the M1 MacBook running around 3 GHz at idle
- that is true even when not actively compiling the JS runtime
- this raises serious questions about day-to-day practicality

This looked especially concerning because the guest was already `aarch64`.

However, direct comparison against Lima's native macOS `vz` backend changed the picture completely:

- `qemu` idle host CPU was in the hundreds of percent
- equivalent `vz` instances idled near effectively zero host CPU

So the problem was not "virtualization on Apple Silicon is too expensive" in general.
The problem was specifically the `qemu` backend for this workflow.

## Current Assessment

The architecture is conceptually sound:

- thin macOS host
- disposable Linux guests
- guest-local project clones
- shared personal CLI environment

After the `vz` pivot, the virtualization layer itself now looks viable.

What is still not adoption-ready is the heavyweight JavaScript runtime story.

Current strengths:

- `vz` gives an efficient VM boundary on this machine
- SSH/bootstrap is working
- guest agent is working
- Nushell can run inside the guest and load scrubs config
- per-repo isolated guests are realistic again

Current weaknesses:

- too much friction around obtaining exact runtime versions cleanly
- `mise` plus NixOS does not yet give an ergonomic "just works" runtime story for repos like `wayforge`
- JavaScript-heavy repos still need a better runtime strategy, likely more Nix-native than pure `mise`

## Current Best Interpretation

We proved that virtualization scrubs is possible.

We also proved that backend choice matters enormously.

Right now the most honest summary is:

- isolation model: promising
- bootstrap path: largely solved
- guest ergonomics: improving
- JavaScript runtime story: poor
- idle performance story on `qemu`: poor
- idle performance story on `vz`: good

## Suggested Next Questions

- Should `vz` become the explicit default and `qemu` only a fallback path?
- Should repo-specific runtimes be provided by Nix overlays instead of `mise` when using NixOS guests?
- Is this model better suited first to non-JS repos or repos with simpler runtime expectations?
- At what point does a container-first approach become more practical than full per-repo VMs?
