#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ensure_plugin_targets || true

overall_status=0

components=( "$SCRIPT_DIR"/components/*.sh )
for target in "${PLUGIN_TARGETS[@]}"; do
  log "uninstall: reverting $target"
  for (( i=${#components[@]}-1; i>=0; i-- )); do
    component="${components[i]}"
    [[ -f "$component" ]] || continue
    # shellcheck source=/dev/null
    source "$component"
    component_name="$(basename "$component" .sh)"
    if revert "$target" "$REPO_DIR"; then
      status=$?
    else
      status=$?
    fi
    case "$status" in
      0)
        log "uninstall: $component_name reverted for $target"
        ;;
      2|3)
        log "uninstall: $component_name not installed for $target"
        ;;
      *)
        log "uninstall: $component_name failed for $target"
        overall_status=1
        ;;
    esac
    unset -f apply 2>/dev/null || true
    unset -f revert
  done
done

remove_session_hook

if [[ "$overall_status" -ne 0 ]]; then
  exit 1
fi

log "uninstall: complete"
