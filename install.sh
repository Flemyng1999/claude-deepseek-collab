#!/usr/bin/env bash
# install.sh — set up claude-deepseek collaboration architecture
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/claude-code"
CLAUDE_DIR="$HOME/.claude"
RULES_DIR="$CLAUDE_DIR/rules"
COMMANDS_DIR="$CLAUDE_DIR/commands"
HOOKS_DIR="$CLAUDE_DIR/hooks"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
RULE_LINE='@~/.claude/rules/deepseek-delegation.md'
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== claude-deepseek-collab installer ==="
echo ""

echo "[1/6] Installing command-line helpers to $BIN_DIR/"
mkdir -p "$BIN_DIR"
cp "$REPO_DIR/bin/claude-deepseek" "$BIN_DIR/claude-deepseek"
cp "$REPO_DIR/bin/claude-deepseek-flash" "$BIN_DIR/claude-deepseek-flash"
cp "$REPO_DIR/scripts/ds-dispatch.sh" "$BIN_DIR/ds-dispatch"
chmod +x "$BIN_DIR/claude-deepseek" "$BIN_DIR/claude-deepseek-flash" "$BIN_DIR/ds-dispatch"
echo "      done"

echo "[2/6] Checking API key config at $CONFIG_DIR/deepseek.env"
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_DIR/deepseek.env" ]]; then
  cp "$REPO_DIR/config/deepseek.env.example" "$CONFIG_DIR/deepseek.env"
  echo "      Created from template — edit $CONFIG_DIR/deepseek.env and add your key"
  echo "      Get a key at: https://platform.deepseek.com/api-keys"
else
  echo "      Already exists, skipping"
fi

echo "[3/6] Installing rules to $RULES_DIR/"
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

echo "[4/6] Installing /ds and /ds-audit to $COMMANDS_DIR/"
mkdir -p "$COMMANDS_DIR"
cp "$REPO_DIR/.claude/commands/ds.md" "$COMMANDS_DIR/ds.md"
cp "$REPO_DIR/.claude/commands/ds-audit.md" "$COMMANDS_DIR/ds-audit.md"
echo "      done"

echo "[5/6] Installing hook helper to $HOOKS_DIR/"
mkdir -p "$HOOKS_DIR"
cp "$REPO_DIR/.claude/hooks/user-prompt-submit.sh" "$HOOKS_DIR/user-prompt-submit.sh"
chmod +x "$HOOKS_DIR/user-prompt-submit.sh"
echo "      done"

echo "[6/6] Wiring rules into $CLAUDE_MD"
mkdir -p "$(dirname "$CLAUDE_MD")"
if [[ -f "$CLAUDE_MD" ]] && grep -qF "$RULE_LINE" "$CLAUDE_MD"; then
  echo "      Already present, skipping"
else
  printf '\n%s\n' "$RULE_LINE" >> "$CLAUDE_MD"
  echo "      Added"
fi

echo ""
echo "=== Installation complete ==="
echo ""

if ! command -v claude-deepseek &>/dev/null || ! command -v ds-dispatch &>/dev/null; then
  echo "NOTE: $BIN_DIR is not in your PATH. Add to ~/.bashrc or ~/.zshrc:"
  echo '  export PATH="$HOME/.local/bin:$PATH"'
  echo ""
fi

echo "Test with:"
echo '  bash scripts/ds-selftest.sh'
echo '  claude-deepseek --print --bare -p "Say hello in one sentence."'
echo ""
echo "After restarting Claude Code, /ds and /ds-audit are available in any project."
