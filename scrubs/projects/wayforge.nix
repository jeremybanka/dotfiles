{ config, lib, pkgs, ... }:
let
  normalUsers = lib.filterAttrs (_: user: user.isNormalUser or false) config.users.users;
  normalUserNames = lib.attrNames normalUsers;
  primaryUser =
    if normalUserNames == [] then null else lib.head normalUserNames;
in
{
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

    # Wayforge currently expects an ambient local Postgres during development.
    # Keep this relaxed setup scoped to the project shim rather than the base VM.
    authentication = lib.mkForce ''
      local all all trust
      host all all 127.0.0.1/32 trust
      host all all ::1/128 trust
    '';
  };
}
