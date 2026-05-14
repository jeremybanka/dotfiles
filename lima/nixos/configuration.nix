{ ... }:
let
  guestUserModule = ./modules/guest-user.nix;
in
{
  imports = [
    ./modules/base.nix
  ] ++ (if builtins.pathExists guestUserModule then [ guestUserModule ] else [ ]);

  system.stateVersion = "25.05";
}
