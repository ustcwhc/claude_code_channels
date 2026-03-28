#!/usr/bin/env bash

apply() {
  local plugin_dir="$1"
  local repo_dir="$2"
  local skill_md="$plugin_dir/skills/access/SKILL.md"
  local patched_skill="$repo_dir/patches/SKILL.md"
  local marker="## Scope resolution"

  [[ -f "$skill_md" ]] || return 3
  [[ -f "$patched_skill" ]] || return 3
  grep -qF "$marker" "$skill_md" 2>/dev/null && return 2

  backup_file "$skill_md" || return 3
  cp "$patched_skill" "$skill_md"
  return 0
}

revert() {
  local plugin_dir="$1"
  local skill_md="$plugin_dir/skills/access/SKILL.md"

  [[ -f "$skill_md" ]] || return 3
  restore_file "$skill_md" && return 0
  return 2
}
