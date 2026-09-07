{
  config,
  lib,
  ...
}:
let
  cfg = config.offline-build-site.hydra;
in
{
  options.offline-build-site.hydra = {
    enable = lib.mkEnableOption "the offline-site Hydra coordinator";

    hydraURL = lib.mkOption {
      type = lib.types.str;
      default = "http://hydra:3000";
    };

    notificationSender = lib.mkOption {
      type = lib.types.str;
      default = "hydra@localhost";
    };

    fodCacheUrl = lib.mkOption {
      type = lib.types.str;
      description = "The FOD cache, the only substituter this site uses.";
    };

    scannerPublicKey = lib.mkOption {
      type = lib.types.str;
      description = "The scanner's nix public key.";
    };

    builders = lib.mkOption {
      description = "Remote builders (each must run offline-build-site.builder).";
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            hostName = lib.mkOption { type = lib.types.str; };
            systems = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "x86_64-linux" ];
            };
            maxJobs = lib.mkOption {
              type = lib.types.int;
              default = 2;
            };
            sshUser = lib.mkOption {
              type = lib.types.str;
              default = "hydra-builder";
            };
            publicHostKeyFile = lib.mkOption {
              type = lib.types.path;
              description = "Pinned SSH host public key of the builder.";
            };
          };
        }
      );
    };

    queueRunnerKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "SSH private key the queue runner uses towards builders.";
    };

    serveReadOnlyKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys (of the signer) that may run a read-only nix-store --serve.";
    };

    hostKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Pinned SSH host key (private part).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.hydra = {
      enable = true;
      hydraURL = cfg.hydraURL;
      notificationSender = cfg.notificationSender;
      # the queue runner substitutes FODs from the cache instead of building them
      useSubstitutes = true;
    };

    nix.settings = {
      substituters = lib.mkForce [ cfg.fodCacheUrl ];
      # not enforced for CA paths, but documents intent and guards any non-CA use
      trusted-public-keys = lib.mkForce [ cfg.scannerPublicKey ];
    };

    # only renders /etc/nix/machines for the queue runner; the daemon never builds remotely
    nix.distributedBuilds = false;
    nix.buildMachines = map (b: {
      inherit (b)
        hostName
        systems
        maxJobs
        sshUser
        ;
      sshKey = "/run/keys-hydra/queue-runner";
    }) cfg.builders;

    programs.ssh.knownHosts = lib.listToAttrs (
      map (b: {
        name = b.hostName;
        value.publicKeyFile = b.publicHostKeyFile;
      }) cfg.builders
    );

    systemd.tmpfiles.settings.hydra-coordinator = {
      "/run/keys-hydra".d = {
        mode = "0750";
        user = "root";
        group = "hydra";
      };
      "/run/keys-hydra/queue-runner"."C+" = {
        mode = "0600";
        user = "hydra-queue-runner";
        group = "hydra";
        argument = cfg.queueRunnerKeyFile;
      };
      "/run/ssh-host-key"."C+" = {
        mode = "0600";
        user = "root";
        group = "root";
        argument = cfg.hostKeyFile;
      };
    };

    users.groups.nix-ro = { };
    users.users.nix-ro = {
      isNormalUser = true;
      group = "nix-ro";
      openssh.authorizedKeys.keys = map (
        key: ''restrict,command="${config.nix.package}/bin/nix-store --serve" ${key}''
      ) cfg.serveReadOnlyKeys;
    };

    services.openssh = {
      enable = true;
      hostKeys = [ ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        AllowUsers = [ "nix-ro" ];
      };
      extraConfig = ''
        HostKey /run/ssh-host-key
      '';
    };

    networking.firewall.allowedTCPPorts = [
      config.services.hydra.port
    ]
    ++ config.services.openssh.ports;
  };
}
