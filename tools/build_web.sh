#!/usr/bin/env bash
# Cloudflare Pages build command: bash tools/build_web.sh
set -euo pipefail

GODOT_VERSION=4.7
build_tools="$(mktemp -d)"
release="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
curl --fail --location --retry 3 -o "$build_tools/godot.zip" "$release/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
unzip -q "$build_tools/godot.zip" -d "$build_tools"
godot="$build_tools/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
chmod +x "$godot"
curl --fail --location --retry 3 -o "$build_tools/templates.tpz" "$release/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
templates_dir="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
mkdir -p "$templates_dir"
unzip -q -o -j "$build_tools/templates.tpz" 'templates/web_*' -d "$templates_dir"

# Import and run regressions before publishing anything.
timeout 180s "$godot" --headless --path . --import
# The suite takes ~90 s on a fast machine; Pages builders are slower, so leave room.
timeout 300s "$godot" --headless --path . -s tests/run_all.gd
timeout 90s "$godot" --headless --path . -s tests/render_shop_tea.gd
timeout 90s "$godot" --headless --path . -s tests/render_shop_pancake.gd

mkdir -p build/web
touch build/.gdignore
timeout 180s "$godot" --headless --path . --export-release Web build/web/index.html

# Launch the exported pack outside the source tree. Packed scenes can differ
# from the source scenes that the interaction regressions load.
web_pack="$PWD/build/web/index.pck"
for shop in pancake tea; do
  smoke_data="$build_tools/pack-smoke-$shop"
  profile_dir="$smoke_data/godot/app_userdata/eatvenLike"
  mkdir -p "$profile_dir"
  printf '{"shop":"%s"}\n' "$shop" > "$profile_dir/profile.json"
  smoke_log="$build_tools/pack-smoke-$shop.log"
  if ! (cd "$build_tools" && XDG_DATA_HOME="$smoke_data" timeout 30s "$godot" --headless --main-pack "$web_pack" --quit-after 8) > "$smoke_log" 2>&1 ||
     grep -Eq '^(SCRIPT ERROR|ERROR):' "$smoke_log" ||
     [ ! -s "$profile_dir/shop_$shop.json" ]; then
    cat "$smoke_log" >&2
    echo "Exported Web pack failed to start shop: $shop" >&2
    exit 1
  fi
  echo "Exported Web pack started shop: $shop"
done

python3 tools/prepare_web_export.py "$PWD/build/web"
# Compression is handled by the loader, so do not add Content-Encoding: gzip.
cat > build/web/_headers <<'HEADERS'
/index.html
  Cache-Control: no-cache
/index.pck
  Cache-Control: no-cache
/index.js
  Cache-Control: no-cache
/index.wasm.gz
  Content-Type: application/gzip
  Cache-Control: no-cache
HEADERS
python3 - <<'PY'
import json
import os
from pathlib import Path
out = Path("build/web")
required = ["index.html", "index.js", "index.pck", "index.wasm.gz"]
for name in required:
    assert (out / name).is_file(), f"Missing Web asset: {name}"
for path in out.rglob("*"):
    if path.is_file() and path.stat().st_size > 25 * 1024 * 1024:
        raise SystemExit(f"Pages asset exceeds 25 MiB: {path}")
(out / "version.json").write_text(json.dumps({
    "commit": os.environ.get("CF_PAGES_COMMIT_SHA", ""),
    "branch": os.environ.get("CF_PAGES_BRANCH", "")
}) + "\n")
print("Web export validated.")
PY
