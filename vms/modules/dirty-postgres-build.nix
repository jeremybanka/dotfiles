{ lib, pkgs, ... }:
let
  buildDeps = with pkgs; [
    readline
    ncurses
    zlib
    openssl
    e2fsprogs
    util-linux
  ];
  toolchainSuffix = builtins.replaceStrings [ "-" ] [ "_" ] pkgs.stdenv.hostPlatform.config;
  buildEnv = rec {
    CPPFLAGS = lib.concatStringsSep " " (map (pkg: "-I${lib.getDev pkg}/include") buildDeps);
    LDFLAGS = lib.concatStringsSep " " (map (pkg: "-L${lib.getLib pkg}/lib") buildDeps);
    # Ordinary compiler invocations need the same paths as configure scripts.
    "NIX_CFLAGS_COMPILE_${toolchainSuffix}" = CPPFLAGS;
    "NIX_LDFLAGS_${toolchainSuffix}" = LDFLAGS;
    PKG_CONFIG_PATH = lib.concatStringsSep ":" [
      (lib.makeSearchPathOutput "dev" "lib/pkgconfig" buildDeps)
      (lib.makeSearchPathOutput "dev" "share/pkgconfig" buildDeps)
    ];
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
