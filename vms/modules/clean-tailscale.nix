{ lib, pkgs, ... }:
# Removal runbook for this emergency binary package:
#
# The readiness signal is that the nixpkgs-unstable revision pinned in
# ../flake.lock evaluates legacyPackages.aarch64-linux.tailscale.version to
# 1.98.9 or newer. Checking the branch alone is not sufficient; update the
# lock first, then evaluate the pinned input with:
#
#   nix eval --raw --impure --expr \
#     'let flake = builtins.getFlake (toString ./vms); in flake.inputs.nixpkgs-unstable.legacyPackages.aarch64-linux.tailscale.version'
#
# When that signal is received, replace this derivation with the ordinary
# unstable package selection below, retain this module's import from
# ../configuration.nix, and validate a disposable guest before rollout:
#
#   { unstablePkgs, ... }:
#   { services.tailscale.package = unstablePkgs.tailscale; }
#
# Confirm `tailscale version` reports 1.98.9 or newer, tailscaled is active,
# and Tailscale SSH works before removing the emergency override everywhere.
let
  version = "1.98.9";
  sources = {
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-+lVO6AjX0H7o4+u8AhXqCHFX4qCrv0CObhjqdTJVTbY=";
    };
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-Eb4wrTAdSPhP9S/sNPii946z497hvk6WJNGfzMjfVUA=";
    };
  };
  source =
    sources.${pkgs.stdenv.hostPlatform.system}
      or (throw "tailscale-bin ${version} does not support ${pkgs.stdenv.hostPlatform.system}");
  tailscale-bin = pkgs.stdenvNoCC.mkDerivation {
    pname = "tailscale";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://pkgs.tailscale.com/stable/tailscale_${version}_${source.arch}.tgz";
      inherit (source) hash;
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 tailscale "$out/bin/tailscale"
      install -Dm755 tailscaled "$out/bin/tailscaled"
      wrapProgram "$out/bin/tailscaled" \
        --prefix PATH : ${
          lib.makeBinPath [
            pkgs.getent
            pkgs.iproute2
            pkgs.iptables
            pkgs.shadow
          ]
        } \
        --suffix PATH : ${lib.makeBinPath [ pkgs.procps ]}

      sed \
        -e "s#/usr/sbin#$out/bin#g" \
        -e "/^EnvironmentFile=/d" \
        systemd/tailscaled.service \
        > tailscaled.service
      install -Dm444 tailscaled.service "$out/lib/systemd/system/tailscaled.service"

      runHook postInstall
    '';

    meta = {
      description = "Node agent for Tailscale, a mesh VPN built on WireGuard";
      homepage = "https://tailscale.com";
      changelog = "https://tailscale.com/changelog#client";
      license = lib.licenses.bsd3;
      mainProgram = "tailscale";
      platforms = builtins.attrNames sources;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  };
in
{
  services.tailscale.package = tailscale-bin;
}
