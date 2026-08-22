#!/usr/bin/env bash
# Validate every skill against Codex's own frontmatter rules.
#
# This is the guard. Claude Code accepts frontmatter keys Codex rejects
# (when-to-use, argument-hint, user-invocable), and Codex additionally rejects
# angle brackets and bare "key: value" colons inside a description. One file
# serving both runtimes only stays valid if something checks.
set -euo pipefail

REPO="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
VALIDATOR="$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py"

if [ ! -f "$VALIDATOR" ]; then
  echo "Codex validator not found at $VALIDATOR" >&2
  echo "Install Codex CLI, or skip validation on this machine." >&2
  exit 2
fi

fail=0
for dir in "$REPO"/skills/*/; do
  name="$(basename "$dir")"
  printf '%-22s ' "$name"
  if python3 "$VALIDATOR" "$dir" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "FAILED"
    python3 "$VALIDATOR" "$dir" 2>&1 | sed 's/^/    /'
    fail=1
  fi
done

exit "$fail"
