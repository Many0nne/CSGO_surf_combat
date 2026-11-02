-- DebugPlaytestRules.luau
-- Règles pures du helper de playtest debug (Studio uniquement, #30) : choix de l'outil, marqueurs attendus,
-- dégâts attendus, visée caméra et rapport PASS/FAIL. Aucune dépendance Roblox au-delà des types de base,
-- pour rester testable sous Lune. Le helper lui-même vit dans `server/DebugPlaytest` et `client/debug/DebugPlaytest`.

local DebugPlaytestRules = {}

-- Préfixe stable de toutes les lignes de log du helper (filtrable dans la sortie console).
DebugPlaytestRules.PREFIX = "[DebugPlaytest]"
-- Attribut posé sur le joueur (contexte Server du MCP) pour lancer un run : nom d'outil ou numéro de slot.
DebugPlaytestRules.ATTRIBUTE = "DebugPlaytest"
-- Marqueur dynamique des armes de mêlée (son résolu au moment de l'impact, cf. WeaponSystem).
DebugPlaytestRules.MELEE_MARKER = "Stab Sound"
-- Distance max (studs) entre la caméra et le centre des pièces visibles d'un viewmodel qui la suit.
DebugPlaytestRules.VIEWMODEL_MAX_DISTANCE = 10

-- Cette méthode permet de résoudre le nom de l'outil à équiper lorsque le sélecteur est un nom (exact, puis
-- insensible à la casse) ou un numéro de slot (index dans les noms triés par ordre alphabétique).
function DebugPlaytestRules.resolveToolName(available: { string }, selector: any): string?
	local names = table.clone(available)
	table.sort(names)
	if type(selector) == "number" then
		return names[selector]
	end
	if type(selector) ~= "string" or selector == "" then
		return nil
	end
	local lower = string.lower(selector)
	local caseInsensitive: string? = nil
	for _, name in names do
		if name == selector then
			return name
		end
		if not caseInsensitive and string.lower(name) == lower then
			caseInsensitive = name
		end
	end
	return caseInsensitive
end

-- Cette méthode permet de lister les animations d'attaque d'une arme lorsqu'on doit reconnaître un tir, alterné ou non.
function DebugPlaytestRules.attackAnimations(cfg: any): { string }
	local animations = table.clone(cfg and cfg.ShootAnimations or { "Shoot" })
	local secondary = cfg and cfg.SecondaryAttack
	if secondary then
		table.insert(animations, secondary.Animation)
	end
	return animations
end

-- Cette méthode permet de lister les marqueurs d'animation à surveiller pour une piste lorsque l'arme déclare
-- ses sons (convention « X Sound ») ; le tir de mêlée ajoute le marqueur dynamique « Stab Sound ».
function DebugPlaytestRules.markersFor(cfg: any, animName: string): { string }
	local markers = {}
	local sounds = cfg and cfg.AnimationSounds and cfg.AnimationSounds[animName]
	if sounds then
		for _, soundName in sounds do
			table.insert(markers, soundName .. " Sound")
		end
	end
	local isAttack = table.find(DebugPlaytestRules.attackAnimations(cfg), animName) ~= nil
	if cfg and cfg.IsMelee and isAttack and not table.find(markers, DebugPlaytestRules.MELEE_MARKER) then
		table.insert(markers, DebugPlaytestRules.MELEE_MARKER)
	end
	return markers
end

-- Cette méthode permet de calculer les dégâts attendus sur la cible immobile lorsqu'elle fait face au joueur
-- (pas de backstab) : ce sont les dégâts de base de l'arme.
function DebugPlaytestRules.expectedDamage(cfg: any): number?
	if not cfg or type(cfg.Damage) ~= "number" then
		return nil
	end
	return cfg.Damage
end

-- Cette méthode permet de convertir une direction monde en angles FPSCamera (degrés) lorsque le helper doit
-- viser la cible ; inverse de `CFrame.Angles(0, rad(-yaw), 0) * CFrame.Angles(rad(pitch), 0, 0)`.
function DebugPlaytestRules.yawPitchToward(
	from: Vector3,
	to: Vector3,
	pitchMin: number,
	pitchMax: number
): (number, number)
	local d = to - from
	if d.Magnitude < 1e-6 then
		return 0, 0
	end
	local u = d.Unit
	local yaw = math.deg(math.atan2(u.X, -u.Z))
	local pitch = math.clamp(math.deg(math.asin(math.clamp(u.Y, -1, 1))), pitchMin, pitchMax)
	return yaw, pitch
end

-- Cette méthode permet de juger si le viewmodel est devant la caméra lorsqu'on a ses points visibles en espace
-- caméra (la caméra regarde vers -Z) : centre devant elle et à moins de VIEWMODEL_MAX_DISTANCE ; renvoie aussi distance et z.
function DebugPlaytestRules.viewmodelInView(cameraSpacePoints: { any }): (boolean, number, number)
	local count = #cameraSpacePoints
	if count == 0 then
		return false, math.huge, 0
	end
	local x, y, z = 0, 0, 0
	for _, point in cameraSpacePoints do
		x += point.X
		y += point.Y
		z += point.Z
	end
	x, y, z = x / count, y / count, z / count
	local distance = math.sqrt(x * x + y * y + z * z)
	return z < 0 and distance <= DebugPlaytestRules.VIEWMODEL_MAX_DISTANCE, distance, z
end

-- Cette méthode permet de lister les dégâts d'un modèle source de viewmodel lorsqu'une synchro Rojo a pu l'abîmer :
-- PrimaryPart absent, enfants physiques en double, joints sans Part0/Part1 ; liste vide si le modèle est sain.
function DebugPlaytestRules.viewmodelDefects(
	hasPrimaryPart: boolean,
	childNames: { string },
	brokenJoints: { string }
): { string }
	local defects = {}
	if not hasPrimaryPart then
		table.insert(defects, "PrimaryPart absent")
	end
	local seen, duplicates = {}, {}
	for _, name in childNames do
		if seen[name] == 1 then
			table.insert(duplicates, name)
		end
		seen[name] = (seen[name] or 0) + 1
	end
	table.sort(duplicates)
	if #duplicates > 0 then
		table.insert(defects, "en double : " .. table.concat(duplicates, ", "))
	end
	if #brokenJoints > 0 then
		table.insert(defects, "joints cassés : " .. table.concat(brokenJoints, ", "))
	end
	return defects
end

-- Cette méthode permet de formater une ligne de log avec le préfixe stable lorsque le helper écrit en console.
function DebugPlaytestRules.line(text: string): string
	return DebugPlaytestRules.PREFIX .. " " .. text
end

export type Step = { name: string, ok: boolean, detail: string }
export type Report = {
	steps: { Step },
	add: (self: Report, name: string, ok: boolean, detail: string?) -> string,
	summary: (self: Report) -> (string, boolean),
}

local Report = {}
Report.__index = Report

-- Cette méthode permet d'enregistrer le résultat d'une étape lorsque le run avance ; renvoie la ligne à logger.
function Report.add(self: Report, name: string, ok: boolean, detail: string?): string
	local step = { name = name, ok = ok, detail = detail or "" }
	table.insert(self.steps, step)
	local text = string.format("%s %s", ok and "PASS" or "FAIL", name)
	if step.detail ~= "" then
		text ..= " : " .. step.detail
	end
	return DebugPlaytestRules.line(text)
end

-- Cette méthode permet de produire la ligne de résultat final lorsque le run se termine :
-- « RESULT PASS n/n » ou « RESULT FAIL k/n (étapes en échec) ».
function Report.summary(self: Report): (string, boolean)
	local failed = {}
	for _, step in self.steps do
		if not step.ok then
			table.insert(failed, step.name)
		end
	end
	local total = #self.steps
	local passed = total - #failed
	local allOk = total > 0 and #failed == 0
	local text = if allOk
		then string.format("RESULT PASS %d/%d", passed, total)
		else string.format("RESULT FAIL %d/%d (%s)", passed, total, table.concat(failed, ", "))
	return DebugPlaytestRules.line(text), allOk
end

-- Cette méthode permet de créer un rapport vide lorsqu'un run démarre.
function DebugPlaytestRules.newReport(): Report
	return setmetatable({ steps = {} }, Report) :: any
end

return DebugPlaytestRules
