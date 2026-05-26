{ lib, pkgs, ... }:
let
  securityRoot = "/opt/security";
  trufflehogVersion = "3.95.2";
  trufflehogAsset =
    if pkgs.stdenv.hostPlatform.system == "aarch64-linux" then
      "trufflehog_3.95.2_linux_arm64.tar.gz"
    else if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
      "trufflehog_3.95.2_linux_amd64.tar.gz"
    else
      throw "security-testing shim only supports aarch64-linux and x86_64-linux";
  trufflehogUrl = "https://github.com/trufflesecurity/trufflehog/releases/download/v${trufflehogVersion}/${trufflehogAsset}";
  linpeasWrapper = pkgs.writeShellScriptBin "linpeas" ''
    exec ${securityRoot}/linpeas/linpeas.sh "$@"
  '';
  trufflehogWrapper = pkgs.writeShellScriptBin "trufflehog" ''
    exec ${securityRoot}/trufflehog/trufflehog "$@"
  '';
  atomicRedTeamWrapper = pkgs.writeShellScriptBin "atomic-red-team" ''
    root="${securityRoot}/atomic-red-team"

    if [ $# -eq 0 ]; then
      printf '%s\n' "$root"
      exit 0
    fi

    cd "$root"
    exec "$@"
  '';
  atomicRedTeamPath = pkgs.writeShellScriptBin "atomic-red-team-path" ''
    printf '%s\n' "${securityRoot}/atomic-red-team"
  '';
  atomicRedTeamUpdate = pkgs.writeShellScriptBin "atomic-red-team-update" ''
    exec sudo systemctl start scrubs-security-tooling.service
  '';
in
{
  environment.systemPackages = with pkgs; [
    linpeasWrapper
    trufflehogWrapper
    atomicRedTeamWrapper
    atomicRedTeamPath
    atomicRedTeamUpdate
    powershell
  ];

  environment.variables = {
    ATOMIC_RED_TEAM_DIR = "${securityRoot}/atomic-red-team";
    LINPEAS_PATH = "${securityRoot}/linpeas/linpeas.sh";
    SCRUBS_SECURITY_ROOT = securityRoot;
    TRUFFLEHOG_VERSION = trufflehogVersion;
  };

  systemd.services.scrubs-security-tooling = {
    description = "Fetch security testing tools for the scrubs security-testing shim";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    path = with pkgs; [
      coreutils
      curl
      git
      gnutar
      gzip
      bash
    ];
    script = ''
      set -euo pipefail

      tmp_dir="$(mktemp -d)"
      atomic_tmp="$tmp_dir/atomic-red-team"
      trap 'rm -rf "$tmp_dir"' EXIT

      install -d -m 0755 ${securityRoot}
      install -d -m 0755 ${securityRoot}/linpeas
      install -d -m 0755 ${securityRoot}/trufflehog

      curl -fsSL "https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh" \
        -o ${securityRoot}/linpeas/linpeas.sh
      chmod 0755 ${securityRoot}/linpeas/linpeas.sh

      curl -fsSL "${trufflehogUrl}" -o "$tmp_dir/trufflehog.tar.gz"
      tar -xzf "$tmp_dir/trufflehog.tar.gz" -C "$tmp_dir"
      install -m 0755 "$tmp_dir/trufflehog" ${securityRoot}/trufflehog/trufflehog

      git clone --depth 1 https://github.com/redcanaryco/atomic-red-team.git "$atomic_tmp"
      rm -rf ${securityRoot}/atomic-red-team
      mv "$atomic_tmp" ${securityRoot}/atomic-red-team
    '';
  };

  system.activationScripts.scrubsSecurityTooling = lib.stringAfter [ "users" ] ''
    ${pkgs.systemd}/bin/systemctl start scrubs-security-tooling.service
  '';
}
