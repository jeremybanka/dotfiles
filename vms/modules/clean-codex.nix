{ lib, pkgs, unstablePkgs, ... }:
let
  # Temporary bridge for Astra support until nixpkgs-unstable catches up.
  # Track https://github.com/NixOS/nixpkgs/pull/559991, then update flake.lock.
  # Keep the complete upstream layout: Codex locates its code-mode host,
  # sandbox helpers, and package metadata relative to its executable.
  version = "0.153.3";
  releases = {
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-I+Yk8NR9j87Qvp1Zq22NBXlfOdUefk6yv/9bNpobmns=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-rL9rZf0vXn1kn5EBwkV6h++uUHWiPn8A9dDFjjzDdsk=";
    };
  };
  release = releases.${pkgs.stdenv.hostPlatform.system};
  codexRelease = pkgs.stdenvNoCC.mkDerivation {
    pname = "codex";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${release.target}.tar.zst";
      inherit (release) hash;
    };

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.zstd
    ];
    # The bundled zsh and rg use shared libraries even in the musl package.
    # Resolve them in the Nix store rather than relying on guest nix-ld config.
    buildInputs = [
      pkgs.ncurses
      pkgs.stdenv.cc.cc.lib
    ];
    sourceRoot = ".";
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r bin codex-package.json codex-path codex-resources "$out/"
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test "$("$out/bin/codex" --version)" = "codex-cli ${version}"
      "$out/bin/codex-code-mode-host" --help > /dev/null
      "$out/codex-path/rg" --version > /dev/null
      "$out/codex-resources/zsh/bin/zsh" --version > /dev/null
      runHook postInstallCheck
    '';

    meta = {
      description = "Codex CLI release shim for scrubs guests";
      homepage = "https://github.com/openai/codex";
      license = lib.licenses.asl20;
      mainProgram = "codex";
      platforms = builtins.attrNames releases;
    };
  };
in
{
  environment.systemPackages = [
    (
      if lib.versionAtLeast unstablePkgs.codex.version version then
        unstablePkgs.codex
      else
        codexRelease
    )
  ];
}
