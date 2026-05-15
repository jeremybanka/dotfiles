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
- per-repo instances work
- the guest can carry shared scrubs tooling and dotfiles
- real repos can be cloned and used inside isolated guests
- Nushell startup issues across macOS and NixOS were debugged and mostly stabilized

In practical terms, we successfully got to:

- a running `scrubs-dev`
- a separate `scrubs-wayforge`
- `jeremybanka/wayforge` cloned inside the guest
- `git`, `nu`, `mise`, and `bun` available in the guest

## Major Obstacles

Two major blockers emerged.

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

### 2. VM overhead on Apple Silicon

The guest is imposing much more background cost than expected.

Observed impact:

- the VM keeps the M1 MacBook running around 3 GHz at idle
- that is true even when not actively compiling the JS runtime
- this raises serious questions about day-to-day practicality

This is especially concerning because the guest is already `aarch64` and should have been closer to a happy path.

## Current Assessment

The architecture is conceptually sound:

- thin macOS host
- disposable Linux guests
- guest-local project clones
- shared personal CLI environment

But the current implementation is not adoption-ready for JavaScript-heavy work.

The biggest reasons are:

- too much guest overhead at idle
- too much friction around obtaining exact runtime versions cleanly
- `mise` plus NixOS does not yet give an ergonomic "just works" runtime story for repos like `wayforge`

## Current Best Interpretation

We proved that virtualization scrubs is possible.

We have not yet proved that it is pleasant enough for routine use on this hardware and toolchain mix.

Right now the most honest summary is:

- isolation model: promising
- bootstrap path: largely solved
- guest ergonomics: mixed
- JavaScript runtime story: poor
- idle performance story: concerning

## Suggested Next Questions

- Can guest idle overhead be materially reduced with different Lima/QEMU settings or a different VM strategy?
- Should repo-specific runtimes be provided by Nix overlays instead of `mise` when using NixOS guests?
- Is this model better suited first to non-JS repos or repos with simpler runtime expectations?
- At what point does a container-first approach become more practical than full per-repo VMs?
