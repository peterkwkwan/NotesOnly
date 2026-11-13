#!/usr/bin/env bash
# Fail firebase hosting predeploy when build/web is incomplete.
# Incomplete deploys look "successful" because firebase.json rewrites ** → index.html,
# so missing main.dart.js / manifest.json return HTML 200 and the app white-screens with:
#   Uncaught SyntaxError: Unexpected token '<' (at main.dart.js:1:1)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
web="$root/build/web"
required=(
  index.html
  flutter_bootstrap.js
  main.dart.js
  manifest.json
  favicon.png
  version.json
  flutter.js
)
missing=0
for f in "${required[@]}"; do
  if [[ ! -f "$web/$f" ]]; then
    echo "error: missing $web/$f" >&2
    missing=1
  fi
done
if [[ ! -d "$web/assets" ]]; then
  echo "error: missing $web/assets/" >&2
  missing=1
fi
if [[ "$missing" -ne 0 ]]; then
  echo "error: run: flutter build web --release" >&2
  exit 1
fi
# Catch the SPA-rewrite footgun if someone deploys a stub.
if head -c 15 "$web/main.dart.js" | grep -q '<!DOCTYPE html'; then
  echo "error: $web/main.dart.js is HTML, not JS — rebuild before deploy" >&2
  exit 1
fi
echo "ok: web hosting bundle looks complete ($(du -h "$web/main.dart.js" | cut -f1) main.dart.js)"
