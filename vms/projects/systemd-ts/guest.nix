{ lib, pkgs, scrubsGuestUser ? null, ... }:
let
  primaryUser = scrubsGuestUser;
  dockerStateRoot =
    if primaryUser == null then null else "/home/${primaryUser}/systemd-ts/.docker";
in
{
  imports = [
    ../../modules/docker-shim.nix
  ];

  environment.systemPackages = with pkgs; [
    acl
  ];

  environment.sessionVariables = lib.mkIf (dockerStateRoot != null) {
    SYSTEMD_TS_TEST_HOST_ROOT = dockerStateRoot;
  };

  system.activationScripts.systemdTsDockerState = lib.mkIf (primaryUser != null) {
    text = ''
      if [ -d /home/${primaryUser}/systemd-ts ]; then
        mkdir -p ${dockerStateRoot}
        mkdir -p ${dockerStateRoot}/tests
        chown ${primaryUser}:users ${dockerStateRoot}
        chown ${primaryUser}:users ${dockerStateRoot}/tests
        chmod 0777 ${dockerStateRoot}
        chmod 0777 ${dockerStateRoot}/tests
        ${pkgs.acl}/bin/setfacl -R -m u:501:rwx,u:1001:rwx ${dockerStateRoot} || true
        ${pkgs.acl}/bin/setfacl -R -d -m u:501:rwx,u:1001:rwx ${dockerStateRoot} || true
      fi
    '';
  };

  systemd.tmpfiles.rules = lib.optional (primaryUser != null)
    "d ${dockerStateRoot} 0777 ${primaryUser} users - -";

}
