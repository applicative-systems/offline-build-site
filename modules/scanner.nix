{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.offline-build-site.scanner;
  fodScanner = pkgs.callPackage ../pkgs/fod-scanner { };
in
{
  options.offline-build-site.scanner = {
    enable = lib.mkEnableOption "the FOD scanning and signing system";

    nixKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Nix store secret key used to sign approved FOD paths.";
    };

    sshKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "SSH private key for the detached bundle signature.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ssh-keygen refuses group/world-readable private keys
    systemd.tmpfiles.settings.scanner = {
      "/run/scanner-keys".d = {
        mode = "0700";
        user = "root";
        group = "root";
      };
      "/run/scanner-keys/nix.sec"."C+" = {
        mode = "0600";
        user = "root";
        group = "root";
        argument = cfg.nixKeyFile;
      };
      "/run/scanner-keys/ssh-sign"."C+" = {
        mode = "0600";
        user = "root";
        group = "root";
        argument = cfg.sshKeyFile;
      };
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "scan-fod-bundle" ''
        exec ${lib.getExe' fodScanner "fod-scanner"} \
          --bundle "$1" --out "$2" \
          --key /run/scanner-keys/nix.sec \
          --ssh-key /run/scanner-keys/ssh-sign
      '')
      fodScanner
    ];
  };
}
