{
  description = "scrubs nixOS guest for sandboxed development on Lima";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Nu 0.116.1 and its aarch64-linux runtime closure are cached at this revision.
    nixpkgs-nushell.url = "github:NixOS/nixpkgs/6eed0e8d420d76dd1c6f4bbfad4e5aa12515bfb6";
  };

  outputs = { nixpkgs, nixpkgs-unstable, nixpkgs-nushell, ... }: {
    nixosConfigurations.scrubs-base = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = {
        unstablePkgs = import nixpkgs-unstable {
          system = "aarch64-linux";
        };
        guestNushell = (import nixpkgs-nushell {
          system = "aarch64-linux";
        }).nushell;
      };
      modules = [ ./configuration.nix ];
    };
  };
}
