{
  description = "scrubs nixOS guest for sandboxed development on Lima";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.scrubs-base = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [ ./configuration.nix ];
    };
  };
}
