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
  };

  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;
      virtualHosts.mirror = {
        default = true;
        root = cfg.webRoot;
        locations."/bundles/".alias = "/var/lib/fod-bundles/";
      };
    };

    systemd.tmpfiles.settings.mirror."/var/lib/fod-bundles".d = {
      mode = "0755";
      user = "root";
      group = "root";
    };

    networking.firewall.allowedTCPPorts = [ 80 ];

    environment.systemPackages = [ (pkgs.callPackage ../pkgs/fod-bundler { }) ];
  };
}
