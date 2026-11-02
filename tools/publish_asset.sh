#!/usr/bin/env bash
# publish_asset.sh
# Publie un asset par Open Cloud, attend la fin de l'opération et écrit son assetId sur la sortie standard.
# Usage : bash tools/publish_asset.sh <fichier> <Animation|Model> <nom>
#   Animation : .rbxm ou .rbxmx contenant une KeyframeSequence
#   Model     : .fbx, .rbxm ou .rbxmx
# La clé (scopes asset:read et asset:write) vient de ROBLOX_OPEN_CLOUD_KEY, ou du fichier ROBLOX_OPEN_CLOUD_KEY_FILE.
# Les assets doivent appartenir au créateur de l'expérience (434916384) pour fonctionner en jeu.

set -u
CREATOR_ID="434916384"
API="https://apis.roblox.com/assets/v1"
POLL_ATTEMPTS=60
POLL_DELAY=2

# Cette méthode permet d'arrêter le script avec un message lorsqu'une étape échoue.
die() {
	echo "publish_asset : $1" >&2
	exit 1
}

# Cette méthode permet de retrouver la clé lorsqu'elle a été définie après le lancement du terminal courant.
# Sous Windows, une variable utilisateur n'atteint que les processus lancés après sa création.
read_key() {
	if [ -n "${ROBLOX_OPEN_CLOUD_KEY:-}" ]; then
		printf '%s' "$ROBLOX_OPEN_CLOUD_KEY"
	elif [ -n "${ROBLOX_OPEN_CLOUD_KEY_FILE:-}" ]; then
		tr -d '\r\n' <"$ROBLOX_OPEN_CLOUD_KEY_FILE"
	elif command -v powershell.exe >/dev/null 2>&1; then
		powershell.exe -NoProfile -Command \
			"[Environment]::GetEnvironmentVariable('ROBLOX_OPEN_CLOUD_KEY','User')" | tr -d '\r\n'
	fi
}

# Cette méthode permet d'échapper une valeur lorsqu'elle est insérée dans une chaîne JSON.
json_escape() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Cette méthode permet de lire un champ texte d'une réponse JSON sur une ligne, sans dépendre de jq.
json_field() {
	printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

[ $# -eq 3 ] || die "usage : bash tools/publish_asset.sh <fichier> <Animation|Model> <nom>"
file="$1"
asset_type="$2"
name="$3"

[ -f "$file" ] || die "fichier introuvable : $file"
extension="$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')"
case "$asset_type:$extension" in
Animation:rbxm | Model:rbxm | Animation:rbxmx | Model:rbxmx) content_type="model/x-rbxm" ;;
Model:fbx) content_type="model/fbx" ;;
Animation:* | Model:*) die "extension .$extension non prise en charge pour le type $asset_type" ;;
*) die "type inconnu : $asset_type (Animation ou Model)" ;;
esac

key="$(read_key)"
[ -n "$key" ] || die "clé Open Cloud manquante (ROBLOX_OPEN_CLOUD_KEY)"

# L'en-tête passe par un fichier privé pour que la clé n'apparaisse pas dans la liste des processus.
header="$(mktemp)"
chmod 600 "$header"
trap 'rm -f "$header"' EXIT
printf 'x-api-key: %s\n' "$key" >"$header"

display="$(json_escape "$name")"
request="{\"assetType\":\"$asset_type\",\"displayName\":\"$display\",\"description\":\"$display\",\"creationContext\":{\"creator\":{\"userId\":\"$CREATOR_ID\"}}}"
reply="$(curl -sS -H @"$header" -F "request=$request" -F "fileContent=@\"$file\";type=$content_type" "$API/assets")" ||
	die "échec de l'envoi"

operation="$(json_field "$reply" operationId)"
[ -n "$operation" ] || operation="$(json_field "$reply" path | sed -n 's|^operations/||p')"
[ -n "$operation" ] || die "envoi refusé : $(printf '%s' "$reply" | head -c 300)"

state=""
for _ in $(seq 1 "$POLL_ATTEMPTS"); do
	state="$(curl -sS -H @"$header" "$API/operations/$operation")" || die "échec de la lecture de l'opération $operation"
	id="$(json_field "$state" assetId)"
	if [ -n "$id" ]; then
		echo "$id"
		exit 0
	fi
	if printf '%s' "$state" | grep -Eq '"(done)"[[:space:]]*:[[:space:]]*true'; then
		die "opération terminée sans asset : $(printf '%s' "$state" | head -c 300)"
	fi
	sleep "$POLL_DELAY"
done
die "opération $operation toujours en cours : $(printf '%s' "$state" | head -c 300)"
