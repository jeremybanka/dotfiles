{ lib, pkgs, unstablePkgs, ... }:
let
  miseExe = lib.getExe unstablePkgs.mise;
  codex = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "codex";
    version = "0.130.0";

    src = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-aarch64-unknown-linux-musl.tar.gz";
      sha256 = "1d7e00f2c22c3016b5bcb71c61010947b022a90e2901bc6baafe82256492c767";
    };

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 codex-aarch64-unknown-linux-musl $out/bin/codex
      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "OpenAI's coding agent that runs in your terminal";
      homepage = "https://github.com/openai/codex";
      license = licenses.asl20;
      platforms = [ "aarch64-linux" ];
      mainProgram = "codex";
    };
  };
in
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
    bubblewrap
    bun
    carapace
    codex
    curl
    delta
    diff-so-fancy
    fd
    git
    gh
    gnupg
    helix
    jq
    lazygit
    unstablePkgs.mise
    ni
    nushell
    ripgrep
    tmux
    wget
  ];

  environment.variables = {
    EDITOR = "hx";
    VISUAL = "hx";
    BASH_ENV = "/etc/bash_env";
  };

  environment.etc."bash_env".text = ''
    # Non-interactive bash never reaches a prompt, so use mise shims there.
    if [ -z "''${SCRUBS_MISE_BASH_ACTIVATED-}" ]; then
      export SCRUBS_MISE_BASH_ACTIVATED=1
      eval "$(${miseExe} activate bash --shims)"
    fi
  '';

  system.activationScripts.limaCompatBash = ''
    mkdir -p /bin
    ln -sf ${pkgs.bashInteractive}/bin/bash /bin/bash
  '';
}
