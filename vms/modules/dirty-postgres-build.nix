{ lib, pkgs, ... }:
let
  buildDeps = with pkgs; [
    readline
    ncurses
    zlib
    openssl
    e2fsprogs
    icu
    util-linux
  ];
  buildEnv = {
    CPPFLAGS = lib.concatStringsSep " " (map (pkg: "-I${lib.getDev pkg}/include") buildDeps);
    LDFLAGS = lib.concatStringsSep " " (map (pkg: "-L${lib.getLib pkg}/lib") buildDeps);
    PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" buildDeps;
    LIBS = "-lncurses";
  };
in
{
  environment.systemPackages = with pkgs; [
    bison
    flex
    gcc
    gnumake
    perl
    pkg-config
  ]
  ++ buildDeps;

  environment.variables = buildEnv;
  environment.sessionVariables = buildEnv;
}
