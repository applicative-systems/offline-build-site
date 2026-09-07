: "${EXPR_PATH:?EXPR_PATH must point at the directory containing release.nix}"
: "${ADMIN_PASSWORD:=admin}"

URL=http://localhost:3000

mycurl() {
  curl --silent --show-error --fail-with-body --referer "$URL" \
    --header "Accept: application/json" --header "Content-Type: application/json" "$@"
}

cookie=$(mktemp)
trap 'rm --force "$cookie"' EXIT

echo ">> logging in" >&2
mycurl --request POST "$URL/login" --cookie-jar "$cookie" \
  --data "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\"}"

echo ">> creating project 'demo'" >&2
mycurl --request PUT "$URL/project/demo" --cookie "$cookie" \
  --data '{"displayname":"Offline Demo","enabled":"1","visible":"1"}'

echo ">> creating jobset 'demo:main'" >&2
mycurl --request PUT "$URL/jobset/demo/main" --cookie "$cookie" --data @- <<EOF
{
  "description": "air-gapped demo jobset",
  "checkinterval": "30",
  "enabled": "1",
  "visible": "1",
  "keepnr": "3",
  "nixexprinput": "src",
  "nixexprpath": "release.nix",
  "inputs": { "src": { "type": "path", "value": "$EXPR_PATH" } }
}
EOF

echo ">> triggering evaluation" >&2
mycurl --request POST "$URL/api/push?jobsets=demo:main" || true
echo >&2
