{
  description = "scrubs nixOS guest for sandboxed development on Lima";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Temporary: the channel's ARM Codex/mise builds were cancelled. These
    # recipes have verified cache.nixos.org outputs; keep normal updates separate.
    nixpkgs-cached-tools.url = "github:NixOS/nixpkgs/7a6522c868711d06e3a520bbcdfafe9806f4337f";
  };

  outputs = { nixpkgs, nixpkgs-unstable, nixpkgs-cached-tools, ... }: {
    nixosConfigurations.scrubs-base = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = let
        cachedToolsPkgs = import nixpkgs-cached-tools {
          system = "aarch64-linux";
        };
      in {
        codexPackage = cachedToolsPkgs.codex;
        misePackage = cachedToolsPkgs.mise;
        unstablePkgs = import nixpkgs-unstable {
          system = "aarch64-linux";
        };
      };
      modules = [ ./configuration.nix ];
    };
  };
}
