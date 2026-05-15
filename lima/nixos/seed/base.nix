{ pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
    AllowAgentForwarding = false;
    X11Forwarding = false;
    UsePAM = false;
  };

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
    settings = {
      system_info = {
        distro = "nixos";
        network.renderers = [ "networkd" ];
        default_user.name = "nixos";
      };

      users = [ "default" ];
      ssh_pwauth = false;
      disable_root = true;
    };
  };

  systemd.network.enable = true;

  boot.growPartition = true;

  system.activationScripts.limaCompatBash = ''
    mkdir -p /bin
    ln -sf ${pkgs.bashInteractive}/bin/bash /bin/bash
  '';

  system.stateVersion = "25.05";
}
