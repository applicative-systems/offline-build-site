{
  config,
  lib,
  ...
}:
let
  cfg = config.offline-build-site.builder;
in
{
  options.offline-build-site.builder = {
    enable = lib.mkEnableOption "air-gapped Hydra remote builder";

    signingKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Nix store secret key; every locally built path is signed with it.";
    };

    queueRunnerPublicKey = lib.mkOption {
      type = lib.types.str;
      description = "SSH public key of Hydra's queue runner.";
    };

    builderUser = lib.mkOption {
      type = lib.types.str;
      default = "hydra-builder";
      description = "User the queue runner logs in as.";
    };

    hostKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Pinned SSH host key (private part).";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      # also covers builds arriving over the serve protocol
      secret-key-files = cfg.signingKeyFile;
      # serve --write imports build inputs through the daemon
      trusted-users = [ cfg.builderUser ];
      # hydra pushes every input, nothing to substitute
      substituters = lib.mkForce [ ];
    };

    users.groups.${cfg.builderUser} = { };
    users.users.${cfg.builderUser} = {
      isNormalUser = true;
      group = cfg.builderUser;
      openssh.authorizedKeys.keys = [
        ''restrict,command="${config.nix.package}/bin/nix-store --serve --write" ${cfg.queueRunnerPublicKey}''
      ];
    };

    systemd.tmpfiles.settings.builder."/run/ssh-host-key"."C+" = {
      mode = "0600";
      user = "root";
      group = "root";
      argument = cfg.hostKeyFile;
    };

    services.openssh = {
      enable = true;
      hostKeys = [ ]; # only the pinned one below
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        AllowUsers = [ cfg.builderUser ];
      };
      extraConfig = ''
        HostKey /run/ssh-host-key
      '';
    };

    networking.firewall.allowedTCPPorts = config.services.openssh.ports;
  };
}
