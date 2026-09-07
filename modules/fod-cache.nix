{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.offline-build-site.fodCache;

  importer = pkgs.writeShellApplication {
    name = "fod-cache-import";
    runtimeInputs = [
      pkgs.openssh
      pkgs.gnutar
      pkgs.zstd
      pkgs.gnugrep
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      if [ $# -ne 2 ]; then
        echo "usage: fod-cache-import <bundle.tar.zst> <bundle.tar.zst.sig>" >&2
        exit 2
      fi
      bundle="$1" sig="$2"

      ssh-keygen -Y verify \
        -f ${cfg.allowedSignersFile} \
        -I ${cfg.signerIdentity} \
        -n fod-bundle \
        -s "$sig" < "$bundle" \
        || { echo "fod-cache-import: REFUSED: bad or missing bundle signature" >&2; exit 1; }

      tmp="${cfg.webRoot}.tmp"
      rm --recursive --force "$tmp"
      mkdir --parents "$tmp"
      tar --directory "$tmp" --zstd --extract --file "$bundle"

      # defense in depth: the scanner already refuses non-CA paths
      for ni in "$tmp"/*.narinfo; do
        grep --quiet '^CA: fixed:' "$ni" \
          || { echo "fod-cache-import: REFUSED: $ni is not content-addressed" >&2; exit 1; }
      done

      chmod --recursive a+rX "$tmp"
      rm --recursive --force "${cfg.webRoot}.old"
      [ ! -e "${cfg.webRoot}" ] || mv "${cfg.webRoot}" "${cfg.webRoot}.old"
      mv "$tmp" "${cfg.webRoot}"
      echo "fod-cache-import: imported $(find "${cfg.webRoot}" -name '*.narinfo' | wc --lines) paths" >&2
    '';
  };
in
{
  options.offline-build-site.fodCache = {
    enable = lib.mkEnableOption "the FOD binary cache";

    webRoot = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/fod-cache";
      description = "Cache directory served by nginx.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 80;
    };

    allowedSignersFile = lib.mkOption {
      type = lib.types.str;
      description = "ssh-keygen -Y allowed_signers file pinning the scanner key.";
    };

    signerIdentity = lib.mkOption {
      type = lib.types.str;
      default = "scanner@demo";
      description = "Signer identity expected in the bundle signature.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;
      virtualHosts.fod-cache = {
        default = true;
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.port;
          }
        ];
        root = cfg.webRoot;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    environment.systemPackages = [ importer ];
  };
}
