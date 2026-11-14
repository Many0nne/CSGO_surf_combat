--!nocheck
-- SpawnCheck.luau
-- Mesure la hauteur des points d'apparition d'une map (dossier GroundSpawns, #328) : sous chaque point, un rayon
-- vertical part de la hauteur où SpawnManager pose la racine (RAY_HEIGHT studs au-dessus du centre du point) et
-- cherche le premier sol que voient les rayons du mouvement (pièces CanQuery). L'écart signé entre la face basse du
-- point et ce sol doit rester sous TOL : le point est au niveau du sol, et le personnage y apparaît pieds au-dessus.
-- Un point sans sol sous lui (vide) ou dans un volume (sol au-dessus de la racine) est fautif.
-- Arithmétique sur des boîtes (RampCheck.box, ShadowCulling.rayEntry) : tourne dans Lune sans Studio. Lancé par
-- tools/rbxm/verify_place.luau (CI) ; testé : tests/specs/SpawnCheck.spec.luau.

local RampCheck = require("./RampCheck")
local ShadowCulling = require("./ShadowCulling")

local SpawnCheck = {}

SpawnCheck.FOLDER = "GroundSpawns"
-- studs : départ du rayon au-dessus du centre du point (racine posée là, SpawnPointRules.ROOT_ABOVE_POINT)
SpawnCheck.RAY_HEIGHT = 5
SpawnCheck.MAX_DROP = 20 -- studs sous la face basse du point : au-delà, pas de sol (vide)
-- studs : écart toléré entre la face basse du point et le sol. Racine posée à 5 studs du centre, rig à 4,77 studs de
-- la racine aux pieds : un point plus bas que le sol de plus de 0,7 stud ferait apparaître les pieds dans le sol.
SpawnCheck.TOL = 0.25

-- Cette méthode permet de mesurer chaque point d'apparition d'une map lorsqu'on vérifie leur hauteur : renvoie
-- { { name, position, floorY (nil : vide), gap (face basse − sol, nil : vide) } } trié par nom.
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
		local bottom = c.Y - point.Size.Y / 2
		local oy = c.Y + SpawnCheck.RAY_HEIGHT
		local best = oy - bottom + SpawnCheck.MAX_DROP
		local found = false
		for _, b in solids do
			local t = ShadowCulling.rayEntry(b, c.X, oy, c.Z, 0, -1, 0, best)
			if t and t <= best then
				best, found = t, true
			end
		end
		local floorY = if found then oy - best else nil
		table.insert(out, {
			name = point.Name,
			position = c,
			floorY = floorY,
			gap = if floorY then bottom - floorY else nil,
		})
	end
	return out
end

-- Cette méthode permet de juger les points d'une map lorsque la CI relit la place : renvoie le bilan (une ligne par
-- point), la liste des messages d'erreur (point vide, ou écart au sol au-delà de TOL) et le plus grand écart mesuré
-- en valeur absolue (math.huge si un point est vide).
function SpawnCheck.check(map)
	local lines, errors, worst = {}, {}, 0
	for _, m in SpawnCheck.measure(map) do
		local where = string.format("%s.%s.%s", map.Name, SpawnCheck.FOLDER, m.name)
		if not m.gap then
			table.insert(errors, string.format("%s : aucun sol à moins de %d studs sous le point", where, SpawnCheck.MAX_DROP))
			table.insert(lines, string.format("  %s : vide", m.name))
			worst = math.huge
		else
			table.insert(lines, string.format("  %s : sol %.3f, écart %+.3f", m.name, m.floorY, m.gap))
			worst = math.max(worst, math.abs(m.gap))
			if math.abs(m.gap) > SpawnCheck.TOL then
				table.insert(
					errors,
					string.format(
						"%s : face basse à %+.3f stud du sol (tolérance %.2f, cf. docs/maps.md)",
						where,
						m.gap,
						SpawnCheck.TOL
					)
				)
			end
		end
	end
	return lines, errors, worst
end

return SpawnCheck
