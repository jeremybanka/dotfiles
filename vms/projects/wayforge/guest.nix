{ lib, pkgs, scrubsGuestUser ? null, ... }:
let
  primaryUser = scrubsGuestUser;
in
{
  imports = [
    ../../modules/clean-postgres.nix
  ];

  environment.systemPackages = with pkgs; [
    gcc
    gnumake
    pkg-config
    python3
    (writeShellScriptBin "python" ''
      exec ${python3}/bin/python3 "$@"
    '')
  ];

  # Wayforge currently expects an ambient local Postgres during development.
  # Keep this relaxed setup scoped to the project shim rather than the base VM.
  services.postgresql.authentication = lib.mkForce ''
    local all all trust
    host all all 127.0.0.1/32 trust
    host all all ::1/128 trust
  '';
}
