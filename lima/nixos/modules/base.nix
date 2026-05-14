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

  programs.git.enable = true;

  environment.systemPackages = with pkgs; [
    bun
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
