#!/usr/bin/env bash
# Link this repo's skills into Claude Code and Codex CLI.
# Idempotent: safe to re-run. Backs up any real file it replaces.
set -euo pipefail

REPO="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
CLAUDE_SKILLS="$HOME/.claude/skills"
CLAUDE_COMMANDS="$HOME/.claude/commands"
CODEX_SKILLS="$HOME/.codex/skills"
BACKUP="$HOME/.claude/skill-backups/install-$(date +%Y%m%d-%H%M%S)"

link() {  # link <source> <target>
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    rm -f "$dst"
  elif [ -e "$dst" ]; then
    mkdir -p "$BACKUP/$(dirname "${dst#$HOME/}")"
    mv "$dst" "$BACKUP/${dst#$HOME/}"
    echo "  backed up $dst"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  echo "  $dst -> $src"
}

mkdir -p "$CLAUDE_SKILLS" "$CLAUDE_COMMANDS" "$CODEX_SKILLS"

for dir in "$REPO"/skills/*/; do
  name="$(basename "$dir")"
  echo "$name:"
  link "${dir}SKILL.md" "$CLAUDE_SKILLS/$name/SKILL.md"
  link "${dir}SKILL.md" "$CODEX_SKILLS/$name/SKILL.md"
  if [ -f "${dir}agents/openai.yaml" ]; then
    link "${dir}agents/openai.yaml" "$CODEX_SKILLS/$name/agents/openai.yaml"
  fi
  # A flat ~/.claude/skills/<name>.md predates the directory layout and shadows it
  if [ -f "$CLAUDE_SKILLS/$name.md" ]; then
    mkdir -p "$BACKUP"
    mv "$CLAUDE_SKILLS/$name.md" "$BACKUP/$name.md"
    echo "  retired flat $CLAUDE_SKILLS/$name.md"
  fi
done

for cmd in "$REPO"/claude-commands/*.md; do
  echo "command $(basename "$cmd"):"
  link "$cmd" "$CLAUDE_COMMANDS/$(basename "$cmd")"
done

echo
echo "Done. Backups (if any): $BACKUP"
