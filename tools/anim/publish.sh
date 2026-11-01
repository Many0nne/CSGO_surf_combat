#!/usr/bin/env bash
# publish.sh
# Publie des animations (.rbxm contenant une KeyframeSequence) par Open Cloud et affiche leurs ids.
# Usage : ROBLOX_OPEN_CLOUD_KEY_FILE=<fichier> bash tools/anim/publish.sh <dossier> <prefixe> <Nom1> [Nom2 ...]
#   exemple : bash tools/anim/publish.sh assets/m9_viewmodel/export M9_ Equip Stab
# La clé (scopes asset:read et asset:write) vient de ROBLOX_OPEN_CLOUD_KEY ou du fichier ROBLOX_OPEN_CLOUD_KEY_FILE.
# Les assets doivent appartenir au créateur de l'expérience (434916384) pour fonctionner en jeu.

set -u
CREATOR_ID="434916384"
API="https://apis.roblox.com/assets/v1"

dir="$1"
prefix="$2"
shift 2

key="${ROBLOX_OPEN_CLOUD_KEY:-}"
if [ -z "$key" ] && [ -n "${ROBLOX_OPEN_CLOUD_KEY_FILE:-}" ]; then
	key="$(tr -d '\r\n' <"$ROBLOX_OPEN_CLOUD_KEY_FILE")"
fi
[ -n "$key" ] || {
	echo "Clé Open Cloud manquante" >&2
	exit 1
}

# L'en-tête passe par un fichier privé pour que la clé n'apparaisse pas dans la liste des processus.
header="$(mktemp)"
chmod 600 "$header"
trap 'rm -f "$header"' EXIT
printf 'x-api-key: %s\n' "$key" >"$header"

status=0
for name in "$@"; do
	display="$prefix$name"
	request="{\"assetType\":\"Animation\",\"displayName\":\"$display\",\"description\":\"$display\",\"creationContext\":{\"creator\":{\"userId\":\"$CREATOR_ID\"}}}"
	reply="$(curl -s -H @"$header" -F "request=$request" -F "fileContent=@$dir/$display.rbxm;type=model/x-rbxm" "$API/assets")"
	operation="$(printf '%s' "$reply" | sed -n 's/.*"operationId":"\([^"]*\)".*/\1/p')"
	[ -n "$operation" ] || operation="$(printf '%s' "$reply" | sed -n 's/.*"path":"operations\/\([^"]*\)".*/\1/p')"
	if [ -z "$operation" ]; then
		echo "$name ERREUR : $(printf '%s' "$reply" | head -c 300)"
		status=1
		continue
	fi
	id=""
	for _ in $(seq 1 30); do
		state="$(curl -s -H @"$header" "$API/operations/$operation")"
		id="$(printf '%s' "$state" | sed -n 's/.*"assetId":"\([0-9]*\)".*/\1/p')"
		[ -n "$id" ] && break
		ping -n 3 127.0.0.1 >/dev/null 2>&1 || sleep 2
	done
	if [ -n "$id" ]; then
		echo "$name=$id"
	else
		echo "$name EN ATTENTE : $(printf '%s' "$state" | head -c 300)"
		status=1
	fi
done
exit "$status"
