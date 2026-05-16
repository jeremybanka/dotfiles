# Bootstrap Cleanup Notes

These are the SSH/bootstrap-era compatibility changes to review once `scrubs` is booting cleanly again.

## Remove Immediately If Still Present

- Do not restore the old `services.cloud-init.config` module-list overrides in [seed/base.nix](/Users/jem/dotfiles/lima/nixos/seed/base.nix).
- Those overrides accidentally disabled Lima's `bootcmd`, which blocked the pre-SSH unlock path entirely.

## Keep For Now

- Keep `services.envfs.enable` plus the `/bin/bash` fallback in [seed/base.nix](/Users/jem/dotfiles/lima/nixos/seed/base.nix).
- Lima still hardcodes `/bin/bash` in parts of its SSH/readiness flow.

- Keep `user.shell = "/bin/sh"` in [lima.yaml](/Users/jem/dotfiles/lima/nixos/lima.yaml).
- This is low-risk and removes one extra variable while the guest bootstrap is unstable.

- Keep the `mode: boot` unlock provision in [lima.yaml](/Users/jem/dotfiles/lima/nixos/lima.yaml).
- Lima-generated cloud-config still sets `lock_passwd: true`, so this is compensating for a real current behavior.

## Revisit After A Clean Boot

- Re-evaluate `UsePAM = false` in [seed/base.nix](/Users/jem/dotfiles/lima/nixos/seed/base.nix).
- It may no longer be necessary once SSH is stable.

- Consider switching away from Lima-managed user creation entirely.
- Lima supports templates with `user: false`, and several official templates use that mode.
- Cleaner long-term shape:
  - seed image owns a declarative bootstrap user
  - Lima stops creating and locking the login user at first boot
  - the unlock-service workaround can be removed

## Preferred Cleanup Order

1. Get one clean `just bootstrap` run from a fresh seed image.
2. Confirm SSH is stable and payload copy plus `nixos-rebuild` both succeed.
3. Decide whether to keep Lima-created users or move to `user: false`.
4. Remove the unlock-script workaround if the seed owns the bootstrap user.
5. Reassess `UsePAM = false`.
