{
  description = "scrubs nixOS guest for sandboxed development on Lima";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs, nixpkgs-unstable, ... }: {
    nixosConfigurations.scrubs-base = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = {
        unstablePkgs = import nixpkgs-unstable {
          system = "aarch64-linux";
        };
      };
      modules = [ ./configuration.nix ];
    };
  };
}
