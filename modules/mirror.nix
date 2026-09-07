# stands in for the internet plus the release engineers' machine
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.offline-build-site.mirror;
in
{
  options.offline-build-site.mirror = {
    enable = lib.mkEnableOption "the demo source mirror";

    webRoot = lib.mkOption {
      type = lib.types.path;
      description = "Directory served at http://<host>/ (the demo source files).";
    };

    bundleDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/fod-bundles";
      description = "Where fod-bundler output lands; served at /bundles/.";
    };

    fodBundlerPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/fod-bundler { };
      description = "The fod-bundler package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;
      virtualHosts.mirror = {
        default = true;
        root = cfg.webRoot;
        locations."/bundles/".alias = "${cfg.bundleDir}/";
      };
    };

    systemd.tmpfiles.settings.mirror.${cfg.bundleDir}.d = {
      mode = "0755";
      user = "root";
      group = "root";
    };

    networking.firewall.allowedTCPPorts = [ 80 ];

    environment.systemPackages = [ cfg.fodBundlerPackage ];
  };
}
