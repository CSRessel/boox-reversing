#!/usr/bin/env bash
set -euo pipefail
ROOT="partition-dumps"
OUT="partition-manifest.tsv"
echo -e "path\tsize_bytes\tsha256" > "$OUT"
while IFS= read -r -d '' f; do
  size=$(stat -c '%s' "$f")
  sha=$(sha256sum "$f" | awk '{print $1}')
  echo -e "${f}\t${size}\t${sha}" >> "$OUT"
done < <(find "$ROOT" -type f -name '*.bin' -print0 | sort -z)
echo "Wrote $OUT"
