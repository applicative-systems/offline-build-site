{
  runCommand,
  nix,
  stdenv,
}:
runCommand "demo-project"
  {
    nativeBuildInputs = [ nix ];
    preferLocalBuild = true;
    allowSubstitutes = false;
  }
  ''
    mkdir --parents $out/webroot $out/nix
    cp --recursive --no-preserve=mode ${./src} $out/webroot/src

    sri() { nix-hash --type sha256 --flat --sri "$1"; }

    substitute ${./release.nix.in} $out/nix/release.nix \
      --subst-var-by SYSTEM ${stdenv.hostPlatform.system} \
      --subst-var-by SERIAL_HASH "$(sri $out/webroot/src/libserialcomm-2.4.rs)" \
      --subst-var-by CONTROLLER_HASH "$(sri $out/webroot/src/pump-controller-1.8.rs)" \
      --subst-var-by EXPORTER_HASH "$(sri $out/webroot/src/audit-log-exporter-1.0.rs)" \
      --subst-var-by LEFTPAD_HASH "$(sri $out/webroot/src/left-pad-1.0.rs)"
  ''
