{ lib, ... }:
{
  nix.settings = {
    # each role declares its own; 60 so their mkForce (50) wins
    substituters = lib.mkOverride 60 [ ];
    trusted-public-keys = lib.mkOverride 60 [ ];
    experimental-features = [ "nix-command" ];
    require-sigs = lib.mkForce true;
    # narinfo caching would make the cache-tampering demos non-deterministic
    narinfo-cache-positive-ttl = 0;
    narinfo-cache-negative-ttl = 0;
  };
}
