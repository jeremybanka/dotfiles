{ ... }:
let
  guestUserModule = ./modules/guest-user.nix;
  runtimeHardwareModule = ./modules/runtime-hardware.nix;
in
{
  imports = [
    ./modules/base.nix
  ]
  ++ (if builtins.pathExists runtimeHardwareModule then [ runtimeHardwareModule ] else [ ])
  ++ (if builtins.pathExists guestUserModule then [ guestUserModule ] else [ ]);

  system.stateVersion = "25.05";
}
