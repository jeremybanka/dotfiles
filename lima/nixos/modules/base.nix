{ pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.hostName = "scrubs";
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

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  programs.git.enable = true;

  security.sudo.wheelNeedsPassword = false;
  users.mutableUsers = false;

  environment.systemPackages = with pkgs; [
    bun
    carapace
    curl
    delta
    fd
    git
    jq
    mise
    nushell
    ripgrep
    vim
    wget
  ];

  environment.variables = {
    EDITOR = "vim";
    VISUAL = "vim";
  };
}
