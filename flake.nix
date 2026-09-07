{
  description = "Air-gapped Hydra build site with a signed FOD supply chain";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = inputs: {
    formatter = builtins.mapAttrs (system: pkgs: pkgs.nixfmt-tree) inputs.nixpkgs.legacyPackages;

    packages = builtins.mapAttrs (
      system: pkgs:
      let
        demoPkgs = pkgs.extend inputs.self.overlays.default;
      in
      {
        demo = inputs.self.checks.${system}.offline-site.driverInteractive;
        inherit (demoPkgs)
          demo-keys
          demo-project
          fod-bundler
          fod-scanner
          ;
      }
    ) inputs.nixpkgs.legacyPackages;

    overlays.default = import ./overlay.nix;

    nixosModules = {
      common = ./modules/common.nix;
      mirror = ./modules/mirror.nix;
      scanner = ./modules/scanner.nix;
      fodCache = ./modules/fod-cache.nix;
      builder = ./modules/builder.nix;
      hydraCoordinator = ./modules/hydra-coordinator.nix;
      signer = ./modules/signer.nix;
      releaseCache = ./modules/release-cache.nix;
      client = ./modules/client.nix;
    };

    checks = builtins.mapAttrs (system: pkgs: {
      offline-site = pkgs.testers.runNixOSTest ./tests/offline-site.nix;
    }) inputs.nixpkgs.legacyPackages;
  };
}
