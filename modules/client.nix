{
  config,
  lib,
  ...
}:
let
  cfg = config.offline-build-site.client;
in
{
  options.offline-build-site.client = {
    enable = lib.mkEnableOption "a release-cache consumer";

    cacheUrl = lib.mkOption {
      type = lib.types.str;
      description = "URL of the release cache.";
    };

    releasePublicKey = lib.mkOption {
      type = lib.types.str;
      description = "The one and only trusted key.";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      substituters = lib.mkForce [ cfg.cacheUrl ];
      trusted-public-keys = lib.mkForce [ cfg.releasePublicKey ];
    };
  };
}
