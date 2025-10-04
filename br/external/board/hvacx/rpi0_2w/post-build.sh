#!/usr/bin/env bash
set -euo pipefail
# Buildroot post-build hook for Tartigrade Step 1
# Ensures our hello script is executable and any small tweaks we need.

TARGET_DIR=${TARGET_DIR:?}

if [[ -f "$TARGET_DIR/etc/init.d/S99hello" ]]; then
  chmod +x "$TARGET_DIR/etc/init.d/S99hello"
fi

# Ensure a friendly issue banner (optional)
if [[ -d "$TARGET_DIR/etc" ]]; then
  echo "Tartigrade Step 1 (Hello World)" > "$TARGET_DIR/etc/issue"
fi

