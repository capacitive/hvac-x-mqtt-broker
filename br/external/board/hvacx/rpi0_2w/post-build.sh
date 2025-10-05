#!/usr/bin/env bash
set -euo pipefail
# Buildroot post-build hook for tardigrade Step 1
# Ensures our hello script is executable and any small tweaks we need.

TARGET_DIR=${TARGET_DIR:?}

if [[ -f "$TARGET_DIR/etc/init.d/S99hello" ]]; then
  chmod +x "$TARGET_DIR/etc/init.d/S99hello"
fi

# Ensure a friendly issue banner (optional) and embed image version
if [[ -d "$TARGET_DIR/etc" ]]; then
  echo "tardigrade Step 1 (Hello World)" > "$TARGET_DIR/etc/issue"
  # Embed version for boot banner
  ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../../../.. && pwd)"
  VER_FILE="$ROOT_DIR/VERSION"
  VER=$(cat "$VER_FILE" 2>/dev/null || echo "v0.1.0")
  printf "%s\n" "$VER" > "$TARGET_DIR/etc/tardigrade-version"
fi

