#!/bin/bash
set -euo pipefail
result_dir="$1"
output_dir="$2"
latest=$(find "$result_dir" -maxdepth 1 -name "*.xcresult" -print 2>/dev/null | sort | tail -n 1)
if [ -z "$latest" ]; then
    echo "No test result bundle found in $result_dir" >&2
    exit 1
fi
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/docknet-attachments.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$output_dir"
xcrun xcresulttool export attachments --path "$latest" --output-path "$tmp_dir" >/dev/null
python3 - "$tmp_dir" "$output_dir" <<'PY'
import json
import shutil
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
manifest = source / "manifest.json"
for entry in json.loads(manifest.read_text()):
    for attachment in entry.get("attachments", []):
        path = source / attachment["exportedFileName"]
        if path.is_file():
            suggested = attachment["suggestedHumanReadableName"]
            name = suggested.split("_0_")[0] + ".png" if "_0_" in suggested else suggested
            shutil.copy2(path, destination / Path(name).name)
shutil.copy2(manifest, destination / "manifest.json")
PY
echo "Screenshots preserved in $output_dir/"
