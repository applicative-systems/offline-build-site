usage() {
  cat <<EOF
usage: fod-scanner --bundle FILE --key FILE --ssh-key FILE --out FILE

  --bundle FILE   input bundle (.tar.zst of a file:// binary cache), from fod-bundler
  --key FILE      nix store secret key; every approved path gets its signature
  --ssh-key FILE  SSH private key for the detached bundle signature (namespace: fod-bundle)
  --out FILE      output bundle; a detached signature is written to FILE.sig
EOF
}

bundle="" key="" sshkey="" outfile=""

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) bundle="$2"; shift 2 ;;
    --key) key="$2"; shift 2 ;;
    --ssh-key) sshkey="$2"; shift 2 ;;
    --out) outfile="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "fod-scanner: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
for req in bundle key sshkey outfile; do
  [ -n "${!req}" ] || { echo "fod-scanner: --${req/sshkey/ssh-key} is required" >&2; exit 2; }
done

export NIX_CONFIG="extra-experimental-features = nix-command"
tmp=$(mktemp --directory)
trap 'rm --recursive --force "$tmp"' EXIT

policy="$tmp/policy"
# not the real EICAR string: the genuine one gets quarantined on whatever
# laptop runs this
cat > "$policy" <<'EOF'
X5O!P%@AP[4\PZX54(P^)7CC)7}$DEMO-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*
EOF

mkdir "$tmp/in"
tar --directory "$tmp/in" --zstd --extract --file "$bundle"

# anything not content-addressed cannot be verified by hash alone
for ni in "$tmp"/in/*.narinfo; do
  grep --quiet '^CA: fixed:' "$ni" \
    || { echo "fod-scanner: REFUSED: $(basename "$ni") is not content-addressed" >&2; exit 1; }
done

sed --quiet 's/^StorePath: //p' "$tmp"/in/*.narinfo | sort --unique > "$tmp/paths"
echo ">> importing $(wc --lines < "$tmp/paths") content-addressed paths" >&2
# no --no-check-sigs: CA paths verify against their content hash on import
xargs --no-run-if-empty nix copy --from "file://$tmp/in" < "$tmp/paths"

# stand-in for a real scanner (clamav, license audit, ...)
verdict=0
while IFS= read -r path; do
  if grep --recursive --quiet --binary-files=without-match --fixed-strings --file "$policy" "$path"; then
    echo "SCAN $path: REJECTED (policy match)" >&2
    verdict=1
  else
    echo "SCAN $path: ok" >&2
  fi
done < "$tmp/paths"
if [ "$verdict" -ne 0 ]; then
  echo "fod-scanner: policy violations found - signing NOTHING" >&2
  exit 1
fi

echo ">> signing store paths with key '$(cut --delimiter=: --fields=1 < "$key")'" >&2
xargs --no-run-if-empty nix store sign --key-file "$key" < "$tmp/paths"

mkdir "$tmp/outc"
xargs --no-run-if-empty nix copy --to "file://$tmp/outc?compression=zstd" < "$tmp/paths"
tar --directory "$tmp/outc" --zstd --create --file "$outfile" .

ssh-keygen -Y sign -f "$sshkey" -n fod-bundle "$outfile"
echo ">> wrote signed bundle $outfile (+ $outfile.sig)" >&2
