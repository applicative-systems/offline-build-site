usage() {
  cat <<EOF
usage: fod-bundler --expr FILE [options]

  --expr FILE      Hydra jobset expression (release.nix)
  --out DIR        output binary cache directory (default: ./fod-cache)
  --tarball FILE   additionally pack the cache into a .tar.zst bundle
  --workers N      nix-eval-jobs workers (default: 2)
  --exclude REGEX  skip jobs whose attribute name matches REGEX
  --allow-ifd      allow import-from-derivation during evaluation
EOF
}

expr="" out="./fod-cache" tarball="" workers=2 exclude='^$' allow_ifd=false

while [ $# -gt 0 ]; do
  case "$1" in
    --expr) expr="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --tarball) tarball="$2"; shift 2 ;;
    --workers) workers="$2"; shift 2 ;;
    --exclude) exclude="$2"; shift 2 ;;
    --allow-ifd) allow_ifd=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "fod-bundler: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$expr" ] || { echo "fod-bundler: --expr is required" >&2; exit 2; }

export NIX_CONFIG="extra-experimental-features = nix-command"
tmp=$(mktemp --directory)
trap 'rm --recursive --force "$tmp"' EXIT

# evaluate like hydra does; --include keeps restrict-eval from refusing
# the expression's own dir
exprdir=$(dirname "$(realpath "$expr")")
echo ">> evaluating jobset $expr" >&2
nix-eval-jobs \
  --workers "$workers" \
  --gc-roots-dir "$tmp/roots" \
  --include "$exprdir" \
  --option restrict-eval true \
  --option allow-import-from-derivation "$allow_ifd" \
  "$expr" > "$tmp/jobs.jsonl"

if jq --exit-status --slurp 'any(.error != null)' "$tmp/jobs.jsonl" > /dev/null; then
  echo "fod-bundler: evaluation errors:" >&2
  jq --raw-output 'select(.error != null) | "  \(.attr): \(.error)"' "$tmp/jobs.jsonl" >&2
  exit 1
fi

jq --raw-output --arg ex "$exclude" \
  'select(.drvPath != null) | select(.attr | test($ex) | not) | .drvPath' \
  "$tmp/jobs.jsonl" | sort --unique > "$tmp/drvs"
excluded=$(jq --raw-output --arg ex "$exclude" 'select(.attr | test($ex)) | .attr' "$tmp/jobs.jsonl" | tr '\n' ' ')
[ -z "$excluded" ] || echo ">> excluded jobs: $excluded" >&2

# fixed-output iff an output pins a hash; (.derivations // .) covers
# nix >= 2.35 and the older flat format
xargs --no-run-if-empty nix derivation show --recursive < "$tmp/drvs" \
  | jq --raw-output '(.derivations // .) | to_entries[]
           | select(any(.value.outputs[]; .hash != null))
           | if (.key | startswith("/")) then .key else "/nix/store/\(.key)" end' \
  | sort --unique > "$tmp/fod-drvs"

n_fods=$(wc --lines < "$tmp/fod-drvs")
if [ "$n_fods" -eq 0 ]; then
  echo "fod-bundler: warning: jobset contains no fixed-output derivations" >&2
else
  echo ">> realizing $n_fods fixed-output derivations (network allowed)" >&2
  xargs --no-run-if-empty nix-store --realise < "$tmp/fod-drvs" > /dev/null
  xargs --no-run-if-empty nix-store --query --outputs < "$tmp/fod-drvs" | sort --unique > "$tmp/fod-outs"

  # deliberately unsigned: signing is the scanner's job
  mkdir --parents "$out"
  echo ">> exporting to binary cache $out" >&2
  xargs --no-run-if-empty nix copy --to "file://$(realpath "$out")?compression=zstd" < "$tmp/fod-outs"
fi

if [ -n "$tarball" ]; then
  tar --directory "$out" --zstd --create --file "$tarball" .
  echo ">> wrote bundle $tarball" >&2
fi
echo ">> bundled $n_fods FOD store paths" >&2
