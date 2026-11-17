{ config, lib, pkgs, ... }:
let
  cfg = config.programs.wayforge-openrig;
in
{
  options.programs.wayforge-openrig.enable = lib.mkEnableOption
    "the pinned clean OpenRig runtime (does not start a rig or install agent hooks)";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ (pkgs.callPackage ./package.nix { }) ];
  };
}
