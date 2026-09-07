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
      trusted-users = [ "hydra-builder" ];
      # hydra pushes every input, nothing to substitute
      substituters = lib.mkForce [ ];
    };

    users.groups.hydra-builder = { };
    users.users.hydra-builder = {
      isNormalUser = true;
      group = "hydra-builder";
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
        AllowUsers = [ "hydra-builder" ];
      };
      extraConfig = ''
        HostKey /run/ssh-host-key
      '';
    };

    networking.firewall.allowedTCPPorts = config.services.openssh.ports;
  };
}
