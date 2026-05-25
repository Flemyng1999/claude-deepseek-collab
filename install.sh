#!/usr/bin/env bash
# install.sh — set up claude-deepseek collaboration architecture
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/claude-code"
RULES_DIR="$HOME/.claude/rules"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
RULE_LINE='@~/.claude/rules/deepseek-delegation.md'
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== claude-deepseek-collab installer ==="
echo ""

# 1. Install wrapper scripts
echo "[1/4] Installing claude-deepseek + claude-deepseek-flash to $BIN_DIR/"
mkdir -p "$BIN_DIR"
cp "$REPO_DIR/bin/claude-deepseek" "$BIN_DIR/claude-deepseek"
chmod +x "$BIN_DIR/claude-deepseek"
cp "$REPO_DIR/bin/claude-deepseek-flash" "$BIN_DIR/claude-deepseek-flash"
chmod +x "$BIN_DIR/claude-deepseek-flash"
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

# 4. Wire routing rules into ~/.claude/CLAUDE.md
echo "[4/4] Wiring rules into $CLAUDE_MD"
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

# PATH reminder if needed
if ! command -v claude-deepseek &>/dev/null; then
  echo "NOTE: $BIN_DIR is not in your PATH. Add to ~/.bashrc or ~/.zshrc:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
fi

echo "Test with:"
echo '  claude-deepseek --print --bare -p "Say hello in one sentence."'
