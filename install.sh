#!/usr/bin/env bash
# install.sh — set up claude-deepseek collaboration architecture
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/claude-code"
RULES_DIR="$HOME/.claude/rules"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== claude-deepseek-collab installer ==="
echo ""

# 1. Install the wrapper script
echo "[1/4] Installing claude-deepseek to $BIN_DIR/"
mkdir -p "$BIN_DIR"
cp "$REPO_DIR/bin/claude-deepseek" "$BIN_DIR/claude-deepseek"
chmod +x "$BIN_DIR/claude-deepseek"
echo "      done"

# 2. Create API key config if not present
echo "[2/4] Checking API key config at $CONFIG_DIR/deepseek.env"
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_DIR/deepseek.env" ]]; then
  cp "$REPO_DIR/config/deepseek.env.example" "$CONFIG_DIR/deepseek.env"
  echo "      Created from template — edit $CONFIG_DIR/deepseek.env and add your key"
  echo "      Get a key at: https://platform.deepseek.com/api-keys"
else
  echo "      Already exists, skipping"
fi

# 3. Install routing rules
echo "[3/4] Installing rules to $RULES_DIR/"
mkdir -p "$RULES_DIR"
if [[ -f "$RULES_DIR/deepseek-delegation.md" ]]; then
  echo "      $RULES_DIR/deepseek-delegation.md already exists"
  read -rp "      Overwrite? [y/N] " REPLY
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    cp "$REPO_DIR/rules/deepseek-delegation.md" "$RULES_DIR/deepseek-delegation.md"
    echo "      Overwritten"
  else
    echo "      Skipped"
  fi
else
  cp "$REPO_DIR/rules/deepseek-delegation.md" "$RULES_DIR/deepseek-delegation.md"
  echo "      done"
fi

# 4. Reminder for CLAUDE.md and settings.json
echo "[4/4] Manual steps required:"
echo ""
echo "  a) Add this line to ~/.claude/CLAUDE.md (or your project CLAUDE.md):"
echo '     @~/.claude/rules/deepseek-delegation.md'
echo ""
echo "  b) Add the following to the SessionStart array in ~/.claude/settings.json:"
cat "$REPO_DIR/hooks/session-start.snippet.json"
echo ""
echo "  c) If $BIN_DIR is not in your PATH, add to ~/.bashrc or ~/.zshrc:"
echo '     export PATH="$HOME/.local/bin:$PATH"'
echo ""
echo "=== Installation complete ==="
echo ""
echo "Test with:"
echo '  claude-deepseek --print --bare -p "Say hello in one sentence."'
