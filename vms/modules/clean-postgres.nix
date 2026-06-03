{ lib, pkgs, scrubsGuestUser ? null, ... }:
let
  primaryUser = scrubsGuestUser;
in
{
  environment.systemPackages = with pkgs; [
    postgresql
  ];

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql;
    ensureDatabases = lib.optional (primaryUser != null) primaryUser;
    ensureUsers = lib.optional (primaryUser != null) {
      name = primaryUser;
      ensureDBOwnership = true;
      ensureClauses = {
        createdb = true;
      };
    };
  };
}
