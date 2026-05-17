{ lib, pkgs, ... }:
let
  dockerStateRoot = "/home/jem/systemd-ts/.docker";
in
{
  environment.systemPackages = with pkgs; [
    acl
    docker-buildx
  ];

  environment.sessionVariables = {
    SYSTEMD_TS_TEST_HOST_ROOT = dockerStateRoot;
  };

  system.activationScripts.systemdTsDockerState = {
    text = ''
      if [ -d /home/jem/systemd-ts ]; then
        mkdir -p ${dockerStateRoot}
        mkdir -p ${dockerStateRoot}/tests
        chown jem:users ${dockerStateRoot}
        chown jem:users ${dockerStateRoot}/tests
        chmod 0777 ${dockerStateRoot}
        chmod 0777 ${dockerStateRoot}/tests
        ${pkgs.acl}/bin/setfacl -R -m u:501:rwx,u:1001:rwx ${dockerStateRoot} || true
        ${pkgs.acl}/bin/setfacl -R -d -m u:501:rwx,u:1001:rwx ${dockerStateRoot} || true
      fi
    '';
  };

  systemd.tmpfiles.rules = [
    "d ${dockerStateRoot} 0777 jem users - -"
  ];

  virtualisation.docker = {
    enable = true;
  };

  users.users.jem = {
    extraGroups = lib.mkAfter [ "docker" ];
  };
}
