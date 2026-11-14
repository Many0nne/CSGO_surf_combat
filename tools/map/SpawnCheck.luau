--!nocheck
-- SpawnCheck.luau
-- Mesure la hauteur des points d'apparition d'une map (dossier GroundSpawns, #328) : sous chaque point, un rayon
-- vertical part de la racine telle que SpawnManager la pose (ROOT_ABOVE_POINT studs au-dessus du centre du point) et
-- cherche le premier sol que voient les rayons du mouvement (pièces CanQuery). L'écart signé entre les pieds du rig
-- posé là (ROOT_TO_FEET sous la racine) et ce sol doit rester dans [0, MAX_FALL] : pieds au-dessus du sol, petite
-- chute. Un point au-dessus du vide ou dans un volume (sol au-dessus de la racine) est fautif.
-- Arithmétique sur des boîtes (RampCheck.box, ShadowCulling.rayEntry) : tourne dans Lune sans Studio. Lancé par
-- tools/rbxm/verify_place.luau (CI) ; testé : tests/specs/SpawnCheck.spec.luau.

local RampCheck = require("./RampCheck")
local ShadowCulling = require("./ShadowCulling")

local SpawnCheck = {}

SpawnCheck.FOLDER = "GroundSpawns"
-- studs : racine posée au-dessus du centre du point, égal à SpawnPointRules.ROOT_ABOVE_POINT (vérifié par le test)
SpawnCheck.ROOT_ABOVE_POINT = 5
-- studs : de la racine aux pieds du StarterCharacter au repos (HipHeight 3,176 + moitié de la racine 1,588), relevé
-- dans Studio : le rig n'est pas dans la place construite par Rojo
SpawnCheck.ROOT_TO_FEET = 4.765
SpawnCheck.MAX_FALL = 1.5 -- studs : pieds plus haut que ça au-dessus du sol, le joueur tombe à l'apparition
SpawnCheck.MAX_DROP = 20 -- studs sous les pieds : au-delà, pas de sol (vide)

-- Cette méthode permet de mesurer chaque point d'apparition d'une map lorsqu'on vérifie leur hauteur : renvoie
-- { { name, position, floorY, gap (pieds − sol) } } trié par nom, floorY et gap nil au-dessus du vide.
function SpawnCheck.measure(map)
	local folder = map:FindFirstChild(SpawnCheck.FOLDER)
	local points, solids = {}, {}
	for _, p in map:GetDescendants() do
		if p:IsA("BasePart") then
			if folder and p.Parent == folder then
				table.insert(points, p)
			elseif p.CanQuery then
				table.insert(solids, RampCheck.box(p))
			end
		end
	end
	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)
	local out = {}
	for _, point in points do
		local c = point.CFrame.Position
		local rootY = c.Y + SpawnCheck.ROOT_ABOVE_POINT
		local feetY = rootY - SpawnCheck.ROOT_TO_FEET
		local best = SpawnCheck.ROOT_TO_FEET + SpawnCheck.MAX_DROP
		local found = false
		for _, b in solids do
			local t = ShadowCulling.rayEntry(b, c.X, rootY, c.Z, 0, -1, 0, best)
			if t and t <= best then
				best, found = t, true
			end
		end
		local floorY = if found then rootY - best else nil
		table.insert(out, {
			name = point.Name,
			position = c,
			floorY = floorY,
			gap = if floorY then feetY - floorY else nil,
		})
	end
	return out
end

-- Cette méthode permet de juger les points d'une map lorsque la CI relit la place : renvoie le bilan par point, les
-- erreurs (vide, pieds sous le sol ou trop haut) et les écarts pieds/sol extrêmes des points qui ont un sol.
function SpawnCheck.check(map)
	local lines, errors, low, high = {}, {}, math.huge, -math.huge
	for _, m in SpawnCheck.measure(map) do
		local where = string.format("%s.%s.%s", map.Name, SpawnCheck.FOLDER, m.name)
		if not m.gap then
			table.insert(errors, string.format("%s : aucun sol à moins de %d studs sous les pieds", where, SpawnCheck.MAX_DROP))
			table.insert(lines, string.format("  %s : vide", m.name))
		else
			table.insert(lines, string.format("  %s : sol %.3f, pieds-sol %+.3f", m.name, m.floorY, m.gap))
			low, high = math.min(low, m.gap), math.max(high, m.gap)
			if m.gap < 0 or m.gap > SpawnCheck.MAX_FALL then
				table.insert(
					errors,
					string.format(
						"%s : pieds à %+.3f stud du sol à l'apparition (attendu 0 à %.1f, cf. docs/maps.md)",
						where,
						m.gap,
						SpawnCheck.MAX_FALL
					)
				)
			end
		end
	end
	return lines, errors, low, high
end

return SpawnCheck
