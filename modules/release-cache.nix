{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.offline-build-site.releaseCache;
in
{
  options.offline-build-site.releaseCache = {
    enable = lib.mkEnableOption "the release binary cache";

    webRoot = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/release-cache";
    };

    uploaderKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "SSH public keys allowed to upload (the signer).";
    };

    hostKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Pinned SSH host key (private part).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;
      virtualHosts.release-cache = {
        default = true;
        root = cfg.webRoot;
      };
    };

    users.groups.uploader = { };
    users.users.uploader = {
      isNormalUser = true;
      group = "uploader";
      openssh.authorizedKeys.keys = map (
        key: ''restrict,command="${lib.getExe' pkgs.rrsync "rrsync"} ${cfg.webRoot}" ${key}''
      ) cfg.uploaderKeys;
    };

    systemd.tmpfiles.settings.release-cache = {
      ${cfg.webRoot}.d = {
        mode = "0755";
        user = "uploader";
        group = "uploader";
      };
      "/run/ssh-host-key"."C+" = {
        mode = "0600";
        user = "root";
        group = "root";
        argument = cfg.hostKeyFile;
      };
    };

    services.openssh = {
      enable = true;
      hostKeys = [ ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        AllowUsers = [ "uploader" ];
      };
      extraConfig = ''
        HostKey /run/ssh-host-key
      '';
    };

    networking.firewall.allowedTCPPorts = [ 80 ] ++ config.services.openssh.ports;
  };
}
