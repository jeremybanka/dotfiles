# Evaluate with the same pkgs used by the Wayforge guest. No system switch.
{ pkgs }:
let
  inherit (pkgs) lib;
  evaluate = enabled: lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      ./module.nix
      ({ lib, ... }: {
        options.environment.systemPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        config = lib.optionalAttrs (enabled != null) {
          programs.wayforge-openrig.enable = enabled;
        };
      })
    ];
  };
  disabled = (evaluate false).config.environment.systemPackages;
  enabled = (evaluate true).config.environment.systemPackages;
in
assert (evaluate null).config.programs.wayforge-openrig.enable == false;
assert disabled == [ ];
assert builtins.length enabled == 1;
assert (builtins.head enabled).pname == "scrubs-openrig";
assert (builtins.head enabled).version == "0.7.3";
{
  disabledByDefault = (evaluate null).config.programs.wayforge-openrig.enable == false;
  optInPackageCount = builtins.length enabled;
}
