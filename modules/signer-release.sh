if [ $# -ne 1 ]; then
  echo "usage: signer-release <store-path>" >&2
  exit 2
fi
path="$1"

builder_names=$(echo "$BUILDER_KEYS" | tr ' ' '\n' | cut --delimiter=: --fields=1 | tr '\n' ' ')
scanner_names=$(echo "$SCANNER_KEYS" | tr ' ' '\n' | cut --delimiter=: --fields=1 | tr '\n' ' ')

echo ">> pulling $path from $HYDRA_TARGET" >&2
NIX_SSHOPTS="-i $SSH_KEY_HYDRA -o UserKnownHostsFile=$KNOWN_HOSTS -o StrictHostKeyChecking=yes" \
  nix copy --from "$HYDRA_TARGET" "$path"

echo ">> auditing closure signatures" >&2
violations=$(nix path-info --json --recursive "$path" | jq --raw-output \
  --arg scan "$scanner_names" --arg build "$builder_names" '
  ($scan | split(" ") | map(select(. != ""))) as $sk
  | ($build | split(" ") | map(select(. != ""))) as $bk
  | to_entries[]
  | (.value.signatures // [] | map(split(":")[0])) as $signers
  | if .value.ca != null then
      if any($signers[]; . as $s | $sk | index($s)) then empty
      else "UNAPPROVED SOURCE (no scanner signature): \(.key)" end
    else
      if any($signers[]; . as $s | $bk | index($s)) then empty
      else "UNTRUSTED BUILD (no builder signature): \(.key)" end
    end')
if [ -n "$violations" ]; then
  echo "$violations" >&2
  echo "signer-release: closure audit FAILED - refusing to release $path" >&2
  exit 1
fi

# the audit above only matched key names
nix store verify --recursive --sigs-needed 1 \
  --trusted-public-keys "$BUILDER_KEYS $SCANNER_KEYS" "$path"

echo ">> signing with release key" >&2
nix store sign --recursive --key-file "$RELEASE_KEY_FILE" "$path"

echo ">> staging to $STAGING_DIR" >&2
nix copy --to "file://$STAGING_DIR?compression=zstd" "$path"

echo ">> pushing to $PUSH_TARGET" >&2
rsync --recursive --links --times \
  --rsh "ssh -i $SSH_KEY_PUSH -o UserKnownHostsFile=$KNOWN_HOSTS -o StrictHostKeyChecking=yes" \
  "$STAGING_DIR"/ "$PUSH_TARGET":
echo ">> released $path" >&2
