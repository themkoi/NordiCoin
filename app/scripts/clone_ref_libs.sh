#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIBS_DIR="$ROOT_DIR/ref_libs"

mkdir -p "$LIBS_DIR"

REPOS=(
  "https://github.com/chipweinberger/flutter_blue_plus.git"
)

for url in "${REPOS[@]}"; do
  name="$(basename "$url" .git)"
  dest="$LIBS_DIR/$name"

  if [ -d "$dest/.git" ]; then
    echo "$name already cloned, skipping"
  else
    echo "Cloning $url → crates/$name ..."
    git clone --depth=1 "$url" "$dest"
  fi
done

echo "Done"
