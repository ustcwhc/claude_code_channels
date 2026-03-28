#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

overall_status=0
if ensure_plugin_targets; then
  for target in "${PLUGIN_TARGETS[@]}"; do
    log "install: patching $target"
    for component in "$SCRIPT_DIR"/components/*.sh; do
      [[ -f "$component" ]] || continue
      # shellcheck source=/dev/null
      source "$component"
      component_name="$(basename "$component" .sh)"
      if apply "$target" "$REPO_DIR"; then
        status=$?
      else
        status=$?
      fi
      case "$status" in
        0)
          log "install: $component_name applied for $target"
          ;;
        2)
          log "install: $component_name already applied for $target"
          ;;
        3)
          log "install: $component_name skipped for $target"
          ;;
        *)
          log "install: $component_name failed for $target"
          overall_status=1
          ;;
      esac
      unset -f apply
      unset -f revert 2>/dev/null || true
    done
  done
else
  log "install: plugin target not found yet - registering hook only"
fi

if [[ "$overall_status" -ne 0 ]]; then
  exit 1
fi

register_session_hook
log "install: complete"
