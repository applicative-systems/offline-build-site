{
  writeShellApplication,
  nix,
  nix-eval-jobs,
  jq,
  gnutar,
  zstd,
  coreutils,
  findutils,
}:
writeShellApplication {
  name = "fod-bundler";
  runtimeInputs = [
    nix
    nix-eval-jobs
    jq
    gnutar
    zstd
    coreutils
    findutils
  ];
  text = builtins.readFile ./fod-bundler.sh;
}
