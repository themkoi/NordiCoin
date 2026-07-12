#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CRATES_DIR="$ROOT_DIR/crates"

mkdir -p "$CRATES_DIR"

REPOS=(
  "https://github.com/embassy-rs/trouble.git"
  "https://github.com/embassy-rs/embassy.git"
  "https://github.com/nrf-rs/nrf-hal.git"
  "https://github.com/embassy-rs/ekv.git"
)

for url in "${REPOS[@]}"; do
  name="$(basename "$url" .git)"
  dest="$CRATES_DIR/$name"

  if [ -d "$dest/.git" ]; then
    echo "$name already cloned, skipping"
  else
    echo "Cloning $url → crates/$name ..."
    git clone --depth=1 "$url" "$dest"
  fi
done

echo "Done"
