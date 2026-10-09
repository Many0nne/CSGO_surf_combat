#!/usr/bin/env bash
# Lint (selene), format (stylua --check) et typecheck (luau-lsp) du dossier src/, puis tests unitaires (Lune).
# Usage : bash tools/check.sh [--fix]   (--fix applique le formatage StyLua)
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.aftman/bin:$PATH"

# Définitions de types alignées sur la version de luau-lsp déclarée dans aftman.toml
LSP_VERSION=$(sed -n 's/^luau-lsp *= *"[^@]*@\([0-9.]*\)".*/\1/p' aftman.toml)
DEFS="tools/globalTypes-$LSP_VERSION.d.luau"
if [ ! -f "$DEFS" ]; then
	curl -sSfL -o "$DEFS" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$LSP_VERSION/scripts/globalTypes.d.luau" || exit 1
fi
rojo sourcemap default.project.json -o sourcemap.json >/dev/null

status=0
echo "== selene"
selene --display-style quiet src || status=1

echo "== stylua"
if [ "${1:-}" = "--fix" ]; then
	stylua src tests
else
	stylua --check src tests >/dev/null 2>&1 && echo "ok" || { echo "fichiers non formatés (bash tools/check.sh --fix)"; status=1; }
fi

echo "== luau-lsp"
luau-lsp analyze --sourcemap=sourcemap.json --definitions="$DEFS" --base-luaurc=.luaurc src || status=1

echo "== tests"
lune run tests/run.luau || status=1

exit $status
