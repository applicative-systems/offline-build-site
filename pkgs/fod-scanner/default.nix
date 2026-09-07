{
  writeShellApplication,
  nix,
  jq,
  openssh,
  gnutar,
  zstd,
  gnugrep,
  gnused,
  coreutils,
  findutils,
}:
writeShellApplication {
  name = "fod-scanner";
  runtimeInputs = [
    nix
    jq
    openssh
    gnutar
    zstd
    gnugrep
    gnused
    coreutils
    findutils
  ];
  text = builtins.readFile ./fod-scanner.sh;
}
