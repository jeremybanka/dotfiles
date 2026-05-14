{ modulesPath, pkgs, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
    AllowAgentForwarding = false;
    X11Forwarding = false;
  };

  services.qemuGuest.enable = true;

  security.sudo.wheelNeedsPassword = false;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  environment.systemPackages = with pkgs; [
    shadow
    sshfs
    sudo
  ];

  services.cloud-init = {
    enable = true;
    network.enable = true;
    config = ''
      system_info:
        distro: nixos
        network:
          renderers: [ "networkd" ]
        default_user:
          name: nixos

      users:
        - default

      ssh_pwauth: false
      disable_root: true

      cloud_init_modules:
        - migrator
        - seed_random
        - growpart
        - resizefs

      cloud_config_modules:
        - disk_setup
        - mounts
        - users-groups
        - set-passwords
        - ssh

      cloud_final_modules: []
    '';
  };

  systemd.network.enable = true;

  boot.growPartition = true;

  system.stateVersion = "25.05";
}
