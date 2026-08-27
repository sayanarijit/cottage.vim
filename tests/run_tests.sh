#!/usr/bin/env bash
set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Running cottage.vim test suite with Neovim..."
nvim --headless -u NONE \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "runtime plugin/cottage.vim" \
  -c "source $PLUGIN_DIR/tests/test_cottage.vim" \
  -c "call RunAllTests()" \
  -c "quitall!"

echo ""
echo "Running cottage.vim test suite with Vim..."
vim -Nu NONE -N \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "runtime plugin/cottage.vim" \
  -c "source $PLUGIN_DIR/tests/test_cottage.vim" \
  -c "call RunAllTests()" \
  -c "quitall!"

echo ""
echo "All tests passed successfully in both Neovim and Vim!"
