{ lib, pkgs, scrubsGuestUser ? null, ... }:
let
  ciUser = "wayfarer-ci";
  ciHome = "/home/${ciUser}";
  workDir = "/var/lib/wayfarer-ci-work";
  runtimeSource = "/home/${scrubsGuestUser}/.local/libexec/scrubs";
  runtimeFiles = [
    "dirty-exec.sh"
    "install-dirty-tools.nu"
    "mise-wrapper.sh"
    "sandbox-policy-lib.nu"
    "sandbox-default-policy.nuon"
  ];
  optionalRuntimeFiles = [ "dprint-parent-args.sh" "parent-guard.py" ];
  initializeTools = pkgs.writeShellScript "wayfarer-ci-initialize-tools" ''
    set -eu
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/.local/share/mise" "$HOME/.local/state/mise"
    /run/current-system/sw/bin/nu --no-config-file "$HOME/.local/libexec/scrubs/install-dirty-tools.nu"
  '';
  cleanupWorkspace = pkgs.writeShellScript "wayfarer-ci-cleanup.sh" ''
    set -eu
    # Job hooks run after action post steps. Only remove this repository's checkout.
    ${pkgs.coreutils}/bin/rm -rf -- ${lib.escapeShellArg "${workDir}/wayfarer/wayfarer"}
  '';
in
{
  assertions = [{
    assertion = scrubsGuestUser != null;
    message = "The Wayfarer runner needs the provisioned scrubs guest user.";
  }];

  users.groups.${ciUser} = { };
  users.users.${ciUser} = {
    isSystemUser = true;
    group = ciUser;
    home = ciHome;
    createHome = true;
    homeMode = "0700";
  };

  systemd.tmpfiles.rules = [
    "d ${workDir} 0700 ${ciUser} ${ciUser} -"
    "d /var/lib/wayfarer-ci-secrets 0700 root root -"
  ];

  # Reuse the provisioned scrubs runtime, never the developer's auth or tool data.
  # This runs separately from the hardened runner, which cannot see /home/jem.
  systemd.services.wayfarer-ci-home = {
    description = "Prepare the isolated Wayfarer CI scrubs home";
    before = [ "github-runner-wayfarer.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      install -d -m 0700 -o ${ciUser} -g ${ciUser} \
        ${ciHome}/.local ${ciHome}/.local/libexec \
        ${ciHome}/.local/share ${ciHome}/.local/state ${ciHome}/.local/bin \
        ${ciHome}/.config \
        ${ciHome}/.local/libexec/scrubs \
        ${ciHome}/.config/mise \
        ${ciHome}/.config/nushell
      ${lib.concatMapStringsSep "\n" (file: ''
        install -m 0555 -o root -g root ${runtimeSource}/${file} ${ciHome}/.local/libexec/scrubs/${file}
      '') runtimeFiles}
      ${lib.concatMapStringsSep "\n" (file: ''
        if test -f ${runtimeSource}/${file}; then
          install -m 0555 -o root -g root ${runtimeSource}/${file} ${ciHome}/.local/libexec/scrubs/${file}
        fi
      '') optionalRuntimeFiles}
      # CI does not need procfs. Omit it rather than weakening the runner's
      # inherited systemd procfs protections to allow a nested procfs mount.
      sed 's/enable_proc: true/enable_proc: false/' \
        ${runtimeSource}/sandbox-default-policy.nuon \
        > ${ciHome}/.local/libexec/scrubs/sandbox-policy.nuon
      chmod 0444 ${ciHome}/.local/libexec/scrubs/sandbox-policy.nuon
      install -m 0444 -o root -g root \
        /home/${scrubsGuestUser}/.config/nushell/local-node-path.nu \
        ${ciHome}/.config/nushell/local-node-path.nu
      cat > ${ciHome}/.config/mise/config.toml <<'EOF'
      [settings]
      experimental = true
      node.compile = false
      EOF
      chmod 0444 ${ciHome}/.config/mise/config.toml
    '';
  };

  services.github-runners.wayfarer = {
    enable = true;
    url = "https://github.com/jeremybanka/wayfarer";
    name = "wayforge-wayfarer";
    extraLabels = [ "wayfarer-ci" ];
    tokenFile = "/var/lib/wayfarer-ci-secrets/registration-token";
    tokenType = "registration";
    replace = true;
    user = ciUser;
    group = ciUser;
    inherit workDir;
    extraPackages = [ pkgs.curl ];
    extraEnvironment = {
      HOME = ciHome;
      ACTIONS_RUNNER_HOOK_JOB_COMPLETED = cleanupWorkspace;
    };
    serviceOverrides = {
      ExecStartPre = lib.mkAfter [ initializeTools ];
      Restart = lib.mkForce "on-failure";
      RestartSec = "10s";
      ProtectHome = lib.mkForce "tmpfs";
      BindPaths = [ ciHome ];
      ReadWritePaths = [ ciHome ];
      # Bubblewrap must create its own user/mount/PID namespaces and drop caps.
      PrivateUsers = lib.mkForce false;
      RestrictNamespaces = lib.mkForce false;
      SystemCallFilter = lib.mkForce [
        "~@clock" "~@cpu-emulation" "~@module" "~@obsolete" "~@raw-io" "~@reboot"
      ];
      CPUQuota = "200%";
      MemoryMax = "4G";
      TasksMax = 1024;
    };
  };

  systemd.services.github-runner-wayfarer = {
    requires = [ "wayfarer-ci-home.service" ];
    after = [ "wayfarer-ci-home.service" ];
  };
}
