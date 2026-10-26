{ unstablePkgs, ... }:
{
  services.tailscale.package = unstablePkgs.tailscale;
}
