{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gcc
    gnumake
    pkg-config
    python3
    (writeShellScriptBin "python" ''
      exec ${python3}/bin/python3 "$@"
    '')
  ];
}
