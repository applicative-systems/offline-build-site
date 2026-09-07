# DEMO ONLY: all secret keys land world-readable in the nix store
{
  runCommand,
  nix,
  openssh,
}:
runCommand "demo-keys"
  {
    nativeBuildInputs = [
      nix
      openssh
    ];
    preferLocalBuild = true;
    allowSubstitutes = false;
  }
  ''
    mkdir --parents $out/cache $out/ssh

    for name in builder1 scanner release; do
      nix --extra-experimental-features nix-command key generate-secret \
        --key-name "demo-$name-1" > "$out/cache/$name.sec"
      nix --extra-experimental-features nix-command key convert-secret-to-public \
        < "$out/cache/$name.sec" > "$out/cache/$name.pub"
    done

    for name in queue-runner signer-hydra signer-cache; do
      ssh-keygen -q -t ed25519 -N "" -C "$name@demo" -f "$out/ssh/$name"
    done

    ssh-keygen -q -t ed25519 -N "" -C "scanner@demo" -f "$out/ssh/scanner-sign"
    printf 'scanner@demo namespaces="fod-bundle" %s\n' \
      "$(cut --delimiter=' ' --fields=1-2 < $out/ssh/scanner-sign.pub)" > $out/ssh/allowed_signers

    for host in hydra builder1 cache; do
      ssh-keygen -q -t ed25519 -N "" -C "host-$host" -f "$out/ssh/host-$host"
      printf '%s %s\n' "$host" "$(cut --delimiter=' ' --fields=1-2 < $out/ssh/host-$host.pub)" \
        >> $out/ssh/known_hosts
    done
  ''
