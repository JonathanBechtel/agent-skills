#!/usr/bin/env bash
# Validate every skill against Codex's own frontmatter rules, and check that
# repo skills are actually reachable from Codex.
#
# This is the guard. Claude Code accepts frontmatter keys Codex rejects
# (when-to-use, argument-hint, user-invocable), and Codex additionally rejects
# angle brackets and bare "key: value" colons inside a description. One file
# serving both runtimes only stays valid if something checks.
#
# Global skills are enforced — they ship to both runtimes, so a failure is a
# failure. Repo skills are reported: whether they satisfy Codex's rules, and
# whether .agents/skills has an entry pointing at them. A skill can be perfectly
# valid and still invisible to Codex, because Codex reads repo-scoped skills
# from .agents/skills, not .claude/skills.
set -euo pipefail

REPO="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
CODEX_CONFIG_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_SKILLS="$CODEX_CONFIG_DIR/skills"
VALIDATOR="$CODEX_SKILLS/.system/skill-creator/scripts/quick_validate.py"

if [ ! -f "$VALIDATOR" ]; then
  echo "Codex validator not found at $VALIDATOR" >&2
  echo "Install Codex CLI, or skip validation on this machine." >&2
  exit 2
fi

if python3 -c 'import yaml' >/dev/null 2>&1; then
  validator_cmd=(python3 "$VALIDATOR")
elif command -v uv >/dev/null 2>&1; then
  validator_cmd=(uv run --quiet --with PyYAML python "$VALIDATOR")
else
  echo "Codex's validator requires PyYAML, but python3 cannot import yaml." >&2
  echo "Install PyYAML or uv, then run this script again." >&2
  exit 2
fi

validate_skill() {
  "${validator_cmd[@]}" "$1"
}

# Codex's default loader walks directories and follows directory symlinks. A
# real SKILL.md is discoverable through either, but a leaf SKILL.md symlink is
# ignored by the walker.
codex_reachable() {
  local entry="$1"
  [ -d "$entry" ] && [ -f "$entry/SKILL.md" ] && [ ! -L "$entry/SKILL.md" ]
}

fail=0

echo "== global (enforced)"
for dir in "$REPO"/skills/*/; do
  printf '  %-22s ' "$(basename "$dir")"
  if validate_skill "$dir" >/dev/null 2>&1; then
    printf 'valid'
  else
    echo "FAILED"
    validate_skill "$dir" 2>&1 | sed 's/^/      /'
    fail=1
    continue
  fi

  name="$(basename "$dir")"
  installed="$CODEX_SKILLS/$name"
  if [ -e "$installed" ] || [ -L "$installed" ]; then
    if codex_reachable "$installed"; then
      echo " · codex-reachable"
    else
      echo " · NOT discoverable (link the skill directory, not SKILL.md)"
      fail=1
    fi
  else
    echo " · not installed"
  fi
done

if [ -d "$REPO/repos" ]; then
  echo
  echo "== repo skills (frontmatter / codex-reachable)"
  for repo in "$REPO"/repos/*/; do
    [ -e "$repo" ] || continue
    rname="$(basename "$repo")"
    root="$(dirname "$(dirname "$(realpath "$repo")")")"   # <checkout>/.claude/skills -> <checkout>
    echo "  $rname:"
    for skill in "$repo"*/; do
      [ -d "$skill" ] || continue
      sname="$(basename "$skill")"
      printf '    %-24s ' "$sname"

      if [ ! -f "${skill}SKILL.md" ]; then
        echo "no SKILL.md"
        continue
      fi

      if validate_skill "$skill" >/dev/null 2>&1; then
        printf 'valid'
      else
        printf 'claude-only'
      fi

      if codex_reachable "$root/.agents/skills/$sname"; then
        echo " · codex-reachable"
      else
        echo " · NOT reachable from Codex (link the whole .agents/skills/$sname directory)"
      fi
    done
    for flat in "$repo"*.md; do
      [ -e "$flat" ] || continue
      printf '    %-24s ' "$(basename "$flat")"
      echo "flat file — Codex cannot load this layout"
    done
  done
fi

exit "$fail"
