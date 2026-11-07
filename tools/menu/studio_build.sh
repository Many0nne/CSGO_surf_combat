#!/usr/bin/env bash
# Assemble le code à envoyer à Studio pour construire ReplicatedStorage.MenuMirrors (#112) : les données générées
# (MenuMirrorsData.luau) en tête, puis tools/menu/studio_build.luau. Écrit .maquettes/studio_build_full.luau.
# Usage (racine du dépôt) : bash tools/menu/studio_build.sh
set -eu
out=".maquettes/studio_build_full.luau"
mkdir -p .maquettes
{
	echo "local DATA = (function()"
	cat src/client/systems/game/MenuMirrorsData.luau
	echo "end)()"
	cat tools/menu/studio_build.luau
} >"$out"
echo "$out"
