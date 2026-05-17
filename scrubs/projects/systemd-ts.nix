{ lib, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    docker-buildx
  ];

  virtualisation.docker = {
    enable = true;
  };

  users.users.jem = {
    extraGroups = lib.mkAfter [ "docker" ];
  };
}
