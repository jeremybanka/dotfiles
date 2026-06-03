{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    python3
    (writeShellScriptBin "python" ''
      exec ${python3}/bin/python3 "$@"
    '')
  ];
}
