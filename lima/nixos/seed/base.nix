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
    UsePAM = false;
  };

  services.qemuGuest.enable = true;
  services.envfs = {
    enable = true;
    extraFallbackPathCommands = ''
      ln -s ${pkgs.bashInteractive}/bin/bash $out/bash
    '';
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

  system.stateVersion = "25.05";
}
