{
  description = "scrubs nixOS guest for sandboxed development on Lima";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Temporary security pin: Tailscale 1.104.2 has a cached aarch64-linux build.
    # Remove once unstable includes the fix or a newer release with a cached ARM build.
    nixpkgs-tailscale.url = "github:NixOS/nixpkgs/7b995718d7e1f4d52aee88f576202de9c63fa703";
  };

  outputs = { nixpkgs, nixpkgs-unstable, nixpkgs-tailscale, ... }: {
    nixosConfigurations.scrubs-base = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = let
        tailscalePkgs = import nixpkgs-tailscale {
          system = "aarch64-linux";
        };
      in {
        tailscalePackage = tailscalePkgs.tailscale;
        unstablePkgs = import nixpkgs-unstable {
          system = "aarch64-linux";
        };
      };
      modules = [ ./configuration.nix ];
    };
  };
}
