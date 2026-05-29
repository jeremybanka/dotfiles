{ lib, pkgs, scrubsGuestUser ? null, ... }:
let
  primaryUser = scrubsGuestUser;
in
{
  environment.systemPackages = with pkgs; [
    docker-buildx
  ];

  virtualisation.docker = {
    enable = true;
  };

  users.users = lib.mkIf (primaryUser != null) {
    "${primaryUser}" = {
      extraGroups = lib.mkAfter [ "docker" ];
    };
  };
}
