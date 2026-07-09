{ pkgs, unstablePkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.hostName = "scrubs";
  networking.useNetworkd = true;
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
    AllowAgentForwarding = false;
    X11Forwarding = false;
  };

  # Scrubs base images are cloned into fresh Lima instances, so they need to
  # keep cloud-init enabled and ready to consume the new NoCloud cidata on
  # every first boot after cloning.
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
  services.resolved.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  programs.git.enable = true;
  programs.nix-ld.enable = true;

  security.sudo.wheelNeedsPassword = false;
  users.mutableUsers = false;

  environment.systemPackages = with pkgs; [
    bottom
    bubblewrap
    carapace
    curl
    delta
    fd
    gcc
    git
    gh
    gnupg
    helix
    jq
    lazygit
    unstablePkgs.codex
    unstablePkgs.mise
    nushell
    openssl
    ripgrep
    tokei
    tmux
    wget
  ];

  environment.variables = {
    EDITOR = "hx";
    VISUAL = "hx";
    MISE_CACHE_DIR = "/tmp/mise-cache";
  };

  systemd.tmpfiles.rules = [
    "d /tmp/mise-cache 1777 root root -"
  ];

  system.activationScripts.limaCompatBash = ''
    mkdir -p /bin
    ln -sf ${pkgs.bashInteractive}/bin/bash /bin/bash
  '';
}
