#!/usr/bin/env bash
# Validate every skill against Codex's own frontmatter rules.
#
# This is the guard. Claude Code accepts frontmatter keys Codex rejects
# (when-to-use, argument-hint, user-invocable), and Codex additionally rejects
# angle brackets and bare "key: value" colons inside a description. One file
# serving both runtimes only stays valid if something checks.
#
# Global skills are enforced — they ship to both runtimes, so a failure is a
# failure. Repo skills are reported only: most are Claude-only by design, and
# whether they satisfy Codex is information, not a verdict.
set -euo pipefail

REPO="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
VALIDATOR="$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py"

if [ ! -f "$VALIDATOR" ]; then
  echo "Codex validator not found at $VALIDATOR" >&2
  echo "Install Codex CLI, or skip validation on this machine." >&2
  exit 2
fi

fail=0

echo "== global (enforced)"
for dir in "$REPO"/skills/*/; do
  printf '  %-22s ' "$(basename "$dir")"
  if python3 "$VALIDATOR" "$dir" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "FAILED"
    python3 "$VALIDATOR" "$dir" 2>&1 | sed 's/^/      /'
    fail=1
  fi
done

if [ -d "$REPO/repos" ]; then
  echo
  echo "== repo skills (reported only)"
  for repo in "$REPO"/repos/*/; do
    [ -e "$repo" ] || continue
    echo "  $(basename "$repo"):"
    for skill in "$repo"*/; do
      [ -d "$skill" ] || continue
      printf '    %-24s ' "$(basename "$skill")"
      if [ ! -f "${skill}SKILL.md" ]; then
        echo "no SKILL.md"
      elif python3 "$VALIDATOR" "$skill" >/dev/null 2>&1; then
        echo "codex-ready"
      else
        echo "claude-only ($(python3 "$VALIDATOR" "$skill" 2>&1 | head -1))"
      fi
    done
    for flat in "$repo"*.md; do
      [ -e "$flat" ] || continue
      printf '    %-24s ' "$(basename "$flat")"
      echo "flat file — not a Codex skill layout"
    done
  done
fi

exit "$fail"
