{ ... }:
let
  guestUserModule = ./modules/guest-user.nix;
  projectShimModule = ./modules/project-shim.nix;
  runtimeHardwareModule = ./modules/runtime-hardware.nix;
  tailscaleConfigModule = ./modules/tailscale-config.nix;
in
{
  imports = [
    ./modules/clean-base.nix
    ./modules/clean-playwright.nix
    ./modules/clean-tailscale.nix
  ]
  ++ (if builtins.pathExists tailscaleConfigModule then [ tailscaleConfigModule ] else [ ])
  ++ (if builtins.pathExists projectShimModule then [ projectShimModule ] else [ ])
  ++ (if builtins.pathExists runtimeHardwareModule then [ runtimeHardwareModule ] else [ ])
  ++ (if builtins.pathExists guestUserModule then [ guestUserModule ] else [ ]);

  system.stateVersion = "25.05";
}
