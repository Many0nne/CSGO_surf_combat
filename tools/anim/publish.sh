#!/usr/bin/env bash
# publish.sh
# Publie plusieurs animations d'un dossier avec tools/publish_asset.sh et affiche leurs ids (Nom=id).
# Usage : bash tools/anim/publish.sh <dossier> <prefixe> <Nom1> [Nom2 ...]
#   exemple : bash tools/anim/publish.sh assets/m9_viewmodel/export M9_ Equip Stab

set -u
script_dir="$(dirname "$0")"

dir="$1"
prefix="$2"
shift 2

status=0
for name in "$@"; do
	display="$prefix$name"
	if id="$(bash "$script_dir/../publish_asset.sh" "$dir/$display.rbxm" Animation "$display")"; then
		echo "$name=$id"
	else
		echo "$name ERREUR" >&2
		status=1
	fi
done
exit "$status"
