#!/usr/bin/env bash
# Create a skill in the right place, wired for both runtimes.
#
#   ./new-skill.sh <name> --global        lives here, installs to ~/.claude and ~/.codex
#   ./new-skill.sh <name> --repo          lives in the repo you are standing in
#   ./new-skill.sh <name> --repo draft-app  lives in that checkout, per repos.conf
#
# Which scope: does the skill name this repo's paths, commands, or conventions?
# Then it is repo-scoped. Would it work unchanged in another checkout? Global.
set -euo pipefail

REPO="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

name="${1:-}"
scope="${2:-}"
target="${3:-}"

if [ -z "$name" ] || [ -z "$scope" ]; then
  sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
fi

case "$name" in
  *[!a-z0-9-]*|-*|*-) echo "Name must be kebab-case: lowercase, digits, inner hyphens." >&2; exit 1 ;;
esac

write_template() {  # write_template <skill-dir> <scope-note>
  mkdir -p "$1"
  cat > "$1/SKILL.md" <<EOF
---
name: $name
description: TODO one or two sentences on what this does, then the triggers - the phrasings and situations that should select it. No angle brackets, and no bare colon-space, both break the Codex parse.
---

# $name

TODO. $2

## When this applies

TODO the conditions under which the procedure below is the right move.

## Procedure

1. TODO
EOF
  echo "  wrote $1/SKILL.md"
}

case "$scope" in
  --global)
    dir="$REPO/skills/$name"
    [ -e "$dir" ] && { echo "$dir already exists." >&2; exit 1; }
    write_template "$dir" "Runtime-neutral: name both primitives where Claude Code and Codex differ."
    mkdir -p "$dir/agents"
    cat > "$dir/agents/openai.yaml" <<EOF
interface:
  display_name: "$(echo "$name" | tr '-' ' ')"
  short_description: "TODO short label for the Codex skill list"
  default_prompt: "Use \$$name to TODO describe a representative request."
EOF
    echo "  wrote $dir/agents/openai.yaml"
    echo
    echo "Next:"
    echo "  1. edit  $dir/SKILL.md"
    echo "  2. $REPO/install.sh     # link into both runtimes"
    echo "  3. $REPO/validate.sh"
    echo "  4. commit and push in $REPO   # this is the sync"
    ;;

  --repo)
    if [ -n "$target" ]; then
      path="$(grep -E "^$target=" "$REPO/repos.conf" | head -1 | cut -d= -f2-)"
      [ -z "$path" ] && { echo "No '$target' in repos.conf." >&2; exit 1; }
      path="${path/#\~/$HOME}"
    else
      path="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      [ -z "$path" ] && { echo "Not inside a git checkout; pass a repo name." >&2; exit 1; }
    fi

    dir="$path/.claude/skills/$name"
    codex_dir="$path/.agents/skills/$name"
    [ -e "$dir" ] && { echo "$dir already exists." >&2; exit 1; }
    if [ -e "$codex_dir" ] || [ -L "$codex_dir" ]; then
      echo "$codex_dir already exists." >&2
      exit 1
    fi
    write_template "$dir" "Repo-scoped: assume this checkout's layout, commands, and conventions."

    mkdir -p "$path/.agents/skills"
    ln -s "../../.claude/skills/$name" "$codex_dir"
    echo "  linked $codex_dir  (Codex skill package)"
    echo
    echo "Next:"
    echo "  1. edit  $dir/SKILL.md"
    echo "  2. commit it in $path   # it belongs to that repo, not to agent-skills"
    echo "  3. run $REPO/validate.sh"
    echo
    echo "Nothing to sync here: repos/ is a live link into that checkout."
    ;;

  *)
    echo "Scope must be --global or --repo." >&2
    exit 1
    ;;
esac
