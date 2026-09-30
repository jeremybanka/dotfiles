{
  description = "scrubs nixOS guest for sandboxed development on Lima";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Codex 0.159.1 bundles GPT-6.1 Sol; update independently of other tools.
    nixpkgs-codex.url = "github:NixOS/nixpkgs/edf8c49b23702fdedec9db25340c69058193485a";
  };

  outputs = { nixpkgs, nixpkgs-unstable, nixpkgs-codex, ... }: {
    nixosConfigurations.scrubs-base = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = {
        codexPackage = (import nixpkgs-codex {
          system = "aarch64-linux";
        }).codex;
        unstablePkgs = import nixpkgs-unstable {
          system = "aarch64-linux";
        };
      };
      modules = [ ./configuration.nix ];
    };
  };
}
