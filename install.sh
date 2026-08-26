#!/usr/bin/env bash
# Link this repo's skills into Claude Code and Codex CLI, and link each
# configured checkout's own skills back into repos/ for one-place browsing.
# Idempotent: safe to re-run. Backs up any real file it replaces.
set -euo pipefail

REPO="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
CLAUDE_SKILLS="$HOME/.claude/skills"
CLAUDE_COMMANDS="$HOME/.claude/commands"
CODEX_CONFIG_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_SKILLS="$CODEX_CONFIG_DIR/skills"
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

echo "== global skills -> both runtimes"
mkdir -p "$CLAUDE_SKILLS" "$CLAUDE_COMMANDS" "$CODEX_SKILLS"

for dir in "$REPO"/skills/*/; do
  dir="${dir%/}"
  name="$(basename "$dir")"
  echo "$name:"
  # Codex discovers SKILL.md while walking skill directories. It follows a
  # directory symlink, but ignores a SKILL.md that is itself a symlink.
  # Linking the package also keeps agents/, scripts/, references/, and assets/
  # available without adding one link per resource.
  link "$dir" "$CLAUDE_SKILLS/$name"
  link "$dir" "$CODEX_SKILLS/$name"
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
echo "== repo skills -> repos/ (links in, files stay in their repo)"
mkdir -p "$REPO/repos"

if [ -f "$REPO/repos.conf" ]; then
  while IFS='=' read -r name path; do
    case "$name" in ''|\#*) continue ;; esac
    path="${path/#\~/$HOME}"
    dst="$REPO/repos/$name"
    if [ ! -d "$path/.claude/skills" ]; then
      echo "  $name: no checkout at $path — skipped"
      rm -f "$dst"
      continue
    fi
    rm -f "$dst"
    ln -s "$path/.claude/skills" "$dst"
    echo "  repos/$name -> $path/.claude/skills"
  done < "$REPO/repos.conf"
fi

echo
echo "Done. Backups (if any): $BACKUP"
