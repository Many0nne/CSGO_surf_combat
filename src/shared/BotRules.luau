-- Règles pures des bots (#133), testées (tests/specs/BotRules.spec.luau) : cap et regard, gêne, choix du nom et du
-- nombre de bots demandé en Studio, bunny hop et air strafe (#151). Règles de navigation : NavRules.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local MathRules = require(ReplicatedStorage.Shared.MathRules)
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)

local BotRules = {}

-- Cette méthode permet de convertir le cap d'un bot (degrés, convention de la caméra FPS) en direction de marche
-- horizontale lorsqu'il avance tout droit.
function BotRules.headingDir(yawDeg: number): Vector3
	local r = math.rad(yawDeg)
	return Vector3.new(math.sin(r), 0, -math.cos(r))
end

-- Cette méthode permet de donner l'orientation de la racine d'un bot qui regarde vers son cap lorsqu'il bouge.
function BotRules.headingRotation(yawDeg: number): CFrame
	return CFrame.Angles(0, math.rad(-yawDeg), 0)
end

-- Cette méthode permet de donner le cap (degrés, convention de la caméra FPS) d'une direction horizontale lorsque le
-- bot doit regarder où il va ; nil pour une direction nulle.
function BotRules.yawOf(dir: Vector3): number?
	if dir.X * dir.X + dir.Z * dir.Z < 1e-8 then
		return nil
	end
	return MathRules.headingDeg(dir.X, dir.Z) % 360
end

-- Cette méthode permet de tourner le regard du bot vers un cap à vitesse limitée lorsqu'il change de direction
-- (rate en °/s), par le plus court côté.
function BotRules.turnToward(yawDeg: number, targetDeg: number, rate: number, dt: number): number
	local delta = MathRules.angleDeltaDeg(yawDeg, targetDeg)
	local maxStep = rate * dt
	return (yawDeg + math.clamp(delta, -maxStep, maxStep)) % 360
end

-- Cette méthode permet de mettre à jour le temps passé gêné lorsqu'un tick au sol est joué : il grandit tant que la
-- vitesse au sol reste sous STUCK_SPEED_RATIO de la vitesse voulue, et revient à 0 sinon (ou en l'air).
function BotRules.stuckTime(previous: number, grounded: boolean, speed: number, wishSpeed: number, dt: number): number
	if not grounded or wishSpeed <= 0 or speed >= wishSpeed * BotConfig.STUCK_SPEED_RATIO then
		return 0
	end
	return previous + dt
end

-- Cette méthode permet de donner un nom à un nouveau bot lorsqu'il entre en jeu : le premier nom de la liste qui
-- n'est pas déjà porté, sinon un nom numéroté.
function BotRules.pickName(taken: { [string]: boolean }): string
	for _, name in BotConfig.NAMES do
		if not taken[name] then
			return name
		end
	end
	local n = #BotConfig.NAMES + 1
	while taken["Bot" .. n] do
		n += 1
	end
	return "Bot" .. n
end

-- Cette méthode permet de répartir les tenues du catalogue entre les noms de bots (#547) lorsqu'on habille un bot : un
-- nom sur deux en origine, les autres pris un à un par la tenue au plus fort poids restant (poids / (portées + 1)).
function BotRules.outfitTable(): { [string]: string }
	local outfits = InventoryRules.outfits()
	local counts: { [string]: number } = {}
	local legendaries = 0
	local result: { [string]: string } = {}
	for i, name in BotConfig.NAMES do
		if i % 2 == 1 then
			local best, bestScore, bestWeight = nil, 0, 0
			for _, outfit in outfits do
				local weight = BotConfig.OUTFIT_WEIGHTS[outfit.rarity or "common"] or 0
				local capped = outfit.rarity == "legendary" and legendaries >= BotConfig.OUTFIT_LEGENDARY_MAX
				local score = weight / ((counts[outfit.id] or 0) + 1)
				-- À score égal, la plus rare passe (une légendaire seule reste visible), puis l'ordre du catalogue
				if not capped and score > 0 and (score > bestScore or (score == bestScore and weight < bestWeight)) then
					best, bestScore, bestWeight = outfit, score, weight
				end
			end
			if best then
				counts[best.id] = (counts[best.id] or 0) + 1
				legendaries += if best.rarity == "legendary" then 1 else 0
				result[name] = best.id
			end
		end
	end
	return result
end

-- Cette méthode permet de donner la tenue d'un bot d'après son nom lorsqu'il apparaît (#521, #547), toujours la même
-- pour un même nom ; nil : tenue d'origine (aussi pour un nom hors de BotConfig.NAMES).
function BotRules.outfitForName(name: string): string?
	return BotRules.outfitTable()[name]
end

-- Bunny hop et air strafe (#151) -----------------------------------------------------------------------------------

-- Cette méthode permet de donner la durée d'un saut sur sol plat lorsqu'on estime la distance parcourue en l'air.
function BotRules.airTime(): number
	return 2 * MovementConfig.JUMP_VELOCITY / -MovementConfig.GRAVITY
end

-- Cette méthode permet de tourner une direction horizontale de deg degrés lorsqu'on décale un cap (sens positif :
-- celui du produit vectoriel X·Z − Z·X positif, cf. signedAngle).
function BotRules.rotateXZ(dir: Vector3, deg: number): Vector3
	local r = math.rad(deg)
	local c, s = math.cos(r), math.sin(r)
	return Vector3.new(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
end

-- Cette méthode permet de mesurer l'angle signé (degrés, −180 à 180) de la direction a vers la direction b à
-- l'horizontale lorsqu'on veut savoir de quel côté tourner.
function BotRules.signedAngle(a: Vector3, b: Vector3): number
	local cross = a.X * b.Z - a.Z * b.X
	local dot = a.X * b.X + a.Z * b.Z
	return math.deg(math.atan2(cross, dot))
end

-- Cette méthode permet de donner l'angle entre la vitesse et la direction voulue qui fait gagner le plus de vitesse
-- en l'air lorsqu'un bot strafe : θ = acos((L − a·t) / |v|), borné à 90° (atteint quand a·t dépasse la limite L).
function BotRules.optimalStrafeAngle(speed: number, wishspeed: number, dt: number): number
	if speed < 1e-3 then
		return 0
	end
	local limit = math.min(wishspeed, MovementConfig.AIR_SPEED_CAP)
	local gain = MovementConfig.AIR_ACCEL * wishspeed * dt
	return math.min(90, math.deg(math.acos(math.clamp((limit - gain) / speed, -1, 1))))
end

-- Cette méthode permet de donner l'angle (au-delà de 90°) qui fait tourner la vitesse sans la changer lorsqu'un bot
-- au plafond doit corriger son cap : l'ajout vaut alors 2L, à l'angle acos(−L / |v|).
function BotRules.steadyTurnAngle(speed: number, wishspeed: number): number
	local limit = math.min(wishspeed, MovementConfig.AIR_SPEED_CAP)
	return math.deg(math.acos(math.clamp(-limit / math.max(speed, 1e-3), -1, 1)))
end

-- Cette méthode permet de donner la vitesse la plus haute qui tient un virage de rayon radius en l'air lorsqu'un bot
-- règle sa vitesse avant un virage : en virage sans gain, la vitesse tourne de 2·asin(L/|v|) par tick, soit un rayon
-- d'environ |v|²·dt / (2L), donc |v| = √(2·L·R / dt), réduit par BHOP_TURN_SAFETY.
function BotRules.turnSpeed(radius: number, dt: number): number
	if radius == math.huge then
		return math.huge
	end
	return math.sqrt(2 * MovementConfig.AIR_SPEED_CAP * math.max(radius, 0) / dt) * BotConfig.BHOP_TURN_SAFETY
end

-- Cette méthode permet de choisir la direction et la vitesse voulues en l'air d'un bot qui bhoppe lorsqu'il vise le
-- cap desired à la vitesse targetSpeed : trop vite, il freine (viser à l'opposé de sa vitesse retire jusqu'à
-- AIR_ACCEL·w·dt par tick, w dosé pour perdre juste l'excès) ; trop lent, angle de gain du côté du cap, décalé de
-- noise (−1 à 1) fois la fenêtre qui fait gagner (±asin(L/|v|) : au-delà, le strafe freine) ; à la vitesse voulue,
-- il plane, ou tourne sans gagner si l'écart dépasse BHOP_ALIGN_TOL. Renvoie (direction, vitesse voulue).
function BotRules.airStrafe(
	velocity: Vector3,
	desired: Vector3,
	targetSpeed: number,
	wishspeed: number,
	dt: number,
	noise: number
): (Vector3, number)
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flat.Magnitude
	if speed < 1 then
		return desired, wishspeed
	end
	local velDir = flat / speed
	local excess = speed - targetSpeed
	if excess > BotConfig.BHOP_SPEED_TOL then
		return -velDir, math.min(wishspeed, excess / (MovementConfig.AIR_ACCEL * dt))
	end
	local err = BotRules.signedAngle(velDir, desired)
	local side = if err >= 0 then 1 else -1
	local angle
	if excess < 0 then
		local limit = math.min(wishspeed, MovementConfig.AIR_SPEED_CAP)
		local window = math.deg(math.asin(math.min(1, limit / speed)))
		angle = BotRules.optimalStrafeAngle(speed, wishspeed, dt) + math.clamp(noise, -1, 1) * window
	elseif math.abs(err) <= BotConfig.BHOP_ALIGN_TOL then
		return Vector3.zero, wishspeed
	else
		angle = BotRules.steadyTurnAngle(speed, wishspeed)
	end
	return BotRules.rotateXZ(velDir, side * angle), wishspeed
end

-- Cette méthode permet de savoir si un bot qui bhoppe ressaute à l'atterrissage lorsqu'il lui reste remaining studs
-- de marche avant un saut, une échelle ou sa destination : le saut suivant doit y tenir, avec une marge.
function BotRules.keepBhopping(remaining: number, speed: number): boolean
	return remaining >= speed * BotRules.airTime() + BotConfig.BHOP_LAND_MARGIN
end

-- Cette méthode permet de donner le temps qui reste avant d'atterrir sur un sol à la hauteur du décollage lorsqu'un
-- bot en l'air règle sa vitesse (vy : vitesse verticale) ; 0 en descente sous la hauteur du décollage.
function BotRules.timeToLand(vy: number): number
	return math.max(0, (vy + MovementConfig.JUMP_VELOCITY) / -MovementConfig.GRAVITY)
end

-- Cette méthode permet de donner la vitesse visée en l'air d'un bot qui bhoppe lorsqu'il règle son strafe : au plus
-- BHOP_MAX_SPEED et la vitesse des virages devant (cornerSpeed), et assez lente pour que la fin de ce saut et le
-- suivant tiennent dans la marche restante (landIn : temps avant d'atterrir), pour arriver au bout à vitesse de
-- course ; jamais sous runSpeed.
function BotRules.bhopTargetSpeed(remaining: number, cornerSpeed: number, runSpeed: number, landIn: number): number
	local fit = (remaining - BotConfig.BHOP_LAND_MARGIN) / (landIn + BotRules.airTime())
	return math.max(runSpeed, math.min(BotConfig.BHOP_MAX_SPEED, cornerSpeed, fit))
end

return BotRules
