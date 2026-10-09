#!/usr/bin/env bash
# Lint (selene), format (stylua --check) et typecheck (luau-lsp) du dossier src/.
# Usage : bash tools/check.sh [--fix]   (--fix applique le formatage StyLua)
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.aftman/bin:$PATH"

DEFS="tools/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	curl -sSfL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
rojo sourcemap default.project.json -o sourcemap.json >/dev/null

status=0
echo "== selene"
selene --display-style quiet src || status=1

echo "== stylua"
if [ "${1:-}" = "--fix" ]; then
	stylua src
else
	stylua --check src >/dev/null 2>&1 && echo "ok" || { echo "fichiers non formatés (bash tools/check.sh --fix)"; status=1; }
fi

echo "== luau-lsp"
luau-lsp analyze --sourcemap=sourcemap.json --definitions="$DEFS" --base-luaurc=.luaurc src || status=1

exit $status
