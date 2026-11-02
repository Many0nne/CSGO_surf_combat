-- HitZones.luau
-- Zones du corps et multiplicateurs de dégâts des armes à distance (#60), d'après les valeurs de CS:GO.
-- Le torse et le ventre forment une seule zone : le HumanoidRootPart, invisible, recouvre les deux et peut
-- intercepter le tir. Le couteau n'utilise pas ces zones (seulement son bonus de dos).

local HitZones = {}

HitZones.Zone = {
	HEAD = "head",
	TORSO = "torso",
	ARMS = "arms",
	LEGS = "legs",
}

HitZones.Multipliers = {
	[HitZones.Zone.HEAD] = 4,
	[HitZones.Zone.TORSO] = 1,
	[HitZones.Zone.ARMS] = 1,
	[HitZones.Zone.LEGS] = 0.75,
}

-- Parties du rig R15, enfants directs du personnage (CharacterConfig.RIG_TYPE).
local ZONE_BY_PART = {
	Head = HitZones.Zone.HEAD,
	UpperTorso = HitZones.Zone.TORSO,
	LowerTorso = HitZones.Zone.TORSO,
	HumanoidRootPart = HitZones.Zone.TORSO,
	LeftUpperArm = HitZones.Zone.ARMS,
	LeftLowerArm = HitZones.Zone.ARMS,
	LeftHand = HitZones.Zone.ARMS,
	RightUpperArm = HitZones.Zone.ARMS,
	RightLowerArm = HitZones.Zone.ARMS,
	RightHand = HitZones.Zone.ARMS,
	LeftUpperLeg = HitZones.Zone.LEGS,
	LeftLowerLeg = HitZones.Zone.LEGS,
	LeftFoot = HitZones.Zone.LEGS,
	RightUpperLeg = HitZones.Zone.LEGS,
	RightLowerLeg = HitZones.Zone.LEGS,
	RightFoot = HitZones.Zone.LEGS,
}

-- Cette méthode permet de trouver la zone d'une partie du corps lorsqu'un tir la touche ; nil si la partie est inconnue.
function HitZones.zoneOf(partName: string?): string?
	return if partName then ZONE_BY_PART[partName] else nil
end

-- Cette méthode permet de calculer les dégâts d'une touche d'après sa zone, arrondis à l'entier inférieur comme dans
-- CS:GO ; une zone inconnue (accessoire, par exemple) vaut ×1.
function HitZones.damageFor(baseDamage: number, zone: string?): number
	local multiplier = if zone then HitZones.Multipliers[zone] else nil
	return math.floor(baseDamage * (multiplier or 1))
end

return HitZones
