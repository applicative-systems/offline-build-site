{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.offline-build-site.signer;

  signerRelease = pkgs.writeShellApplication {
    name = "signer-release";
    runtimeInputs = [
      pkgs.nix
      pkgs.jq
      pkgs.rsync
      pkgs.openssh
    ];
    text = ''
      # nix-ro and uploader: the users hydra-coordinator.nix and release-cache.nix create
      export HYDRA_TARGET="ssh://nix-ro@${cfg.hydra.host}"
      export SSH_KEY_HYDRA=/run/keys-signer/ssh-hydra
      export SSH_KEY_PUSH=/run/keys-signer/ssh-push
      export KNOWN_HOSTS=${cfg.knownHostsFile}
      export BUILDER_KEYS=${lib.escapeShellArg (lib.concatStringsSep " " cfg.trustedBuilderKeys)}
      export SCANNER_KEYS=${lib.escapeShellArg (lib.concatStringsSep " " cfg.scannerPublicKeys)}
      export RELEASE_KEY_FILE=/run/keys-signer/release.sec
      export STAGING_DIR=/var/lib/signer/staging
      export PUSH_TARGET="uploader@${cfg.push.host}"
      ${builtins.readFile ./signer-release.sh}
    '';
  };
in
{
  options.offline-build-site.signer = {
    enable = lib.mkEnableOption "the release signer";

    hydra = {
      host = lib.mkOption { type = lib.types.str; };
      keyFile = lib.mkOption {
        type = lib.types.str;
        description = "SSH private key for the read-only store access on hydra.";
      };
    };

    trustedBuilderKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Nix public keys of all builders whose work may be released.";
    };

    scannerPublicKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Nix public keys of the scanners; every CA path must carry one.";
    };

    releaseSecretKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "The release signing key. Lives ONLY on this machine.";
    };

    push = {
      host = lib.mkOption { type = lib.types.str; };
      keyFile = lib.mkOption {
        type = lib.types.str;
        description = "SSH private key for the rrsync-jailed upload to the release cache.";
      };
    };

    knownHostsFile = lib.mkOption {
      type = lib.types.str;
      description = "Pinned host keys for hydra and the release cache.";
    };
  };

  config = lib.mkIf cfg.enable {
    # the most sensitive machine of the site, hence nothing inbound
    assertions = [
      {
        assertion = !config.services.openssh.enable;
        message = "the signer must not run sshd - it accepts no inbound connections";
      }
    ];

    # import-time verification for everything pulled from hydra
    nix.settings.trusted-public-keys = lib.mkForce (cfg.trustedBuilderKeys ++ cfg.scannerPublicKeys);

    systemd.tmpfiles.settings.signer = {
      "/run/keys-signer".d = {
        mode = "0700";
        user = "root";
        group = "root";
      };
      "/run/keys-signer/ssh-hydra"."C+" = {
        mode = "0600";
        user = "root";
        group = "root";
        argument = cfg.hydra.keyFile;
      };
      "/run/keys-signer/ssh-push"."C+" = {
        mode = "0600";
        user = "root";
        group = "root";
        argument = cfg.push.keyFile;
      };
      "/run/keys-signer/release.sec"."C+" = {
        mode = "0600";
        user = "root";
        group = "root";
        argument = cfg.releaseSecretKeyFile;
      };
      "/var/lib/signer/staging".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
    };

    environment.systemPackages = [ signerRelease ];
  };
}
