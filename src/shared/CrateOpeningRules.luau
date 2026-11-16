-- Chronologie de l'ouverture d'une caisse (#332, docs/ui.md « Ouverture d'une caisse ») : règles pures, testées
-- (tests/specs/CrateOpeningRules.spec.luau). La scène (ShopScene, CrateOpening) lit ici, à chaque image, l'état de
-- chaque effet au temps `t` (secondes depuis le clic OUVRIR).
--
-- Temps relevés sur la référence validée par l'utilisateur, les packs d'Apex Legends
-- (references/anim/apex-packs-toutes-raretes.mp4, ouverture 1 : 28,0 s de la vidéo = 0 ici) :
-- - charge 28,0 → 31,0 s : calme 0,2 s, crépitements, bouffées de lumière à 28,8 / 29,2 / 29,5-29,8 (rayons) /
--   29,9 / 30,4 / 30,9 s, gerbes d'étincelles à 30,0 et 30,5 s ; la caméra avance pendant 0,8 s. Ici étirée ×1,5
--   (CHARGE_SCALE), et la lumière sort par la fente du couvercle, pas par le dessus (elle traversait le couvercle) ;
-- - explosion 31,0 s, le dessus du pack part 31,2 → 31,4 s ;
-- - colonne de lumière, puis silhouette de l'objet en lumière unie, révélation 0,43 à 0,83 s après la colonne
--   (33,67 / 34,30 / 41,50 s). La pause d'Apex entre l'explosion et la colonne (robot, objets posés au sol) est retirée :
--   une caisse ne donne qu'un objet.
-- Retours de l'utilisateur sur les vidéos côte à côte (pas dans Apex) :
-- - montée de couleur par paliers pendant la charge : la lumière part de la couleur du commun et monte d'un palier sur
--   certaines bouffées (TIER_AT) jusqu'à la rareté tirée ; l'explosion, la colonne et la silhouette sont dans la
--   couleur finale ;
-- - fin trop rapide face à la charge : tension avant l'explosion (la caisse tremble de plus en plus fort et se soulève,
--   la fente sature, puis un temps d'arrêt), colonne qui grandit depuis la caisse, braises, et silhouette qui s'élève
--   lentement (RISE_TIME) avant de tenir HOLD s selon la rareté.
local CrateOpeningRules = {}

export type Pulse = { at: number, power: number, rays: boolean, hold: number }
export type State = {
	push: number, -- avancée de la caméra vers la caisse, 0 → 1
	shake: number, -- amplitude des secousses de la caisse, 0 → 1
	lift: number, -- soulèvement de la caisse au-dessus du socle (tension avant l'explosion), 0 → 1
	glow: number, -- lueur de la rareté dans la caisse (fente du couvercle, puis caisse ouverte), 0 → 1
	rays: number, -- lumière qui jaillit par la fente du couvercle, 0 → 1 (chaque bouffée)
	flash: number, -- éclair (explosion, révélation), 0 → 1
	lid: number, -- vol du couvercle, 0 (en place) → 1 (posé derrière le socle)
	column: number, -- opacité de la colonne de lumière, 0 → 1
	columnHeight: number, -- hauteur de la colonne, part de sa hauteur finale (elle grandit depuis la caisse)
	columnWidth: number, -- largeur de la colonne, part de sa largeur d'apparition
	embers: number, -- débit des braises qui montent de la caisse ouverte, 0 → 1
	silhouette: number, -- opacité de l'arme en lumière unie, 0 → 1
	revealed: boolean, -- l'arme habillée de son skin est montrée
	rise: number, -- montée de l'arme hors de la caisse, 0 → 1
	spin: number, -- rotation de l'arme sur elle-même, en degrés
	tier: number, -- palier de couleur de la lumière (rang dans TIERS), de 1 à celui de la rareté tirée
}

-- Charge étirée ×1,5 par rapport à Apex (retour de l'utilisateur : « un peu trop rapide », la montée de couleur n'avait
-- pas le temps d'être lue) : instants de la référence × CHARGE_SCALE
CrateOpeningRules.CHARGE_SCALE = 1.5
CrateOpeningRules.CRACKLE_START = 0.3
CrateOpeningRules.PUSH_TIME = 0.8
-- Bouffées : la lumière jaillit par la fente entre la caisse et le couvercle (`rays`) ; `hold` : la plus longue (la
-- bouffée à rayons d'Apex, 29,5-29,8 s). La dernière tombe au début du temps d'arrêt : seule sa lueur reste
CrateOpeningRules.PULSES = {
	{ at = 1.2, power = 0.7, rays = false, hold = 0 },
	{ at = 1.8, power = 0.8, rays = false, hold = 0 },
	{ at = 2.25, power = 1.0, rays = true, hold = 0.45 },
	{ at = 2.85, power = 0.9, rays = false, hold = 0 },
	{ at = 3.6, power = 0.85, rays = false, hold = 0 },
	{ at = 4.35, power = 1.0, rays = false, hold = 0 },
} :: { Pulse }
CrateOpeningRules.PULSE_ATTACK = 0.03 -- une image : les bouffées d'Apex éclatent d'un coup
CrateOpeningRules.PULSE_DECAY = 0.35
CrateOpeningRules.SPARKS = { 3.0, 3.75, 4.5 } -- gerbes d'étincelles ; la dernière est celle de l'explosion
CrateOpeningRules.BURST = 4.5
CrateOpeningRules.BURST_FLASH = 0.3
-- Tension : de TENSION_START au temps d'arrêt, secousses, soulèvement et lueur montent jusqu'au plein ; pendant le
-- temps d'arrêt (PAUSE s avant l'explosion), plus rien ne bouge, la caisse reste soulevée et pleine de lumière ;
-- à l'explosion, elle retombe sur le socle en LIFT_DROP s
CrateOpeningRules.TENSION_START = 3.9
CrateOpeningRules.PAUSE = 0.15
CrateOpeningRules.LIFT_DROP = 0.08
CrateOpeningRules.LID_START = 4.7
CrateOpeningRules.LID_TIME = 0.4 -- à 0,6, le couvercle restait dressé derrière la colonne
CrateOpeningRules.COLUMN = 5.0
CrateOpeningRules.COLUMN_GROW = 0.3 -- la colonne grandit depuis la caisse (Apex : en une image, trop sec ici)
CrateOpeningRules.COLUMN_SETTLE = 0.3 -- puis se resserre et s'atténue derrière la silhouette
CrateOpeningRules.COLUMN_REST = 0.35 -- opacité de la colonne derrière la silhouette
CrateOpeningRules.COLUMN_FADE = 0.4 -- extinction après la révélation
CrateOpeningRules.SILHOUETTE_FADE = 0.3 -- apparition de la silhouette dans la colonne
CrateOpeningRules.REVEAL_FLASH = 0.15
CrateOpeningRules.RISE_TIME = 1.0 -- montée de la silhouette hors de la caisse (0,12 s : elle « sautait »)
-- Tenue de la silhouette en haut, avant la révélation, par rareté (le suspense croît avec la rareté ; LÉGENDAIRE, #430,
-- la plus longue)
CrateOpeningRules.HOLD = { common = 0.3, rare = 0.5, exceptional = 0.7, legendary = 1.1 } :: { [string]: number }
CrateOpeningRules.DEFAULT_HOLD = 0.5
-- Rotation de l'arme : de trois quarts au profil, jamais par la tranche (deux tours complets montraient la silhouette
-- par la tranche, une tache sans forme, à la moitié du suspense)
CrateOpeningRules.SPIN_FROM = 70
CrateOpeningRules.SPIN_AFTER = 0.6 -- la rotation finit de ralentir après la révélation
CrateOpeningRules.SWAY = 8 -- balancement de tenue, en degrés
-- Paliers de couleur, de la rareté la plus courante à la plus rare (même ordre que ShopCatalog.RARITIES, vérifié par
-- le test). TIER_AT[k] : passage au palier k + 1, sur une bouffée de la charge (la bouffée fait le sursaut) : RARE sur
-- la bouffée à rayons, EXCEPTIONNEL puis LÉGENDAIRE (#430) sur les deux suivantes, avant la tension ; la tension et
-- l'explosion confirment la couleur finale
CrateOpeningRules.TIERS = { "common", "rare", "exceptional", "legendary" }
CrateOpeningRules.TIER_AT = { 2.25, 2.85, 3.6 }

-- Cette méthode permet de borner une valeur entre 0 et 1 lorsqu'une phase est convertie en progression.
local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- Cette méthode permet d'adoucir le départ et l'arrivée d'une progression (smoothstep) lorsque la caméra avance ou que
-- l'arme monte.
local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

-- Cette méthode permet de donner le temps de la révélation (colonne, montée de la silhouette, tenue selon la rareté)
-- lorsque l'ouverture démarre ou que le joueur clique pour passer.
function CrateOpeningRules.revealTime(rarityId: string?): number
	local R = CrateOpeningRules
	local hold = rarityId and R.HOLD[rarityId] or R.DEFAULT_HOLD
	return R.COLUMN + R.RISE_TIME + hold
end

-- Cette méthode permet de donner le rang d'une rareté dans les paliers de couleur (1 si inconnue) lorsque la montée de
-- couleur est calculée.
function CrateOpeningRules.tierOf(rarityId: string?): number
	return rarityId and table.find(CrateOpeningRules.TIERS, rarityId) or 1
end

-- Cette méthode permet de donner l'instant où la lumière passe au palier `tier` (2 ou plus) lorsque la montée de
-- couleur est échantillonnée ; au-delà des paliers prévus, l'explosion.
function CrateOpeningRules.tierTime(tier: number): number
	return CrateOpeningRules.TIER_AT[tier - 1] or CrateOpeningRules.BURST
end

-- Cette méthode permet de donner l'intensité d'une bouffée de lumière au temps `t` (montée en une image, tenue,
-- extinction en PULSE_DECAY) lorsque la charge est échantillonnée.
local function pulseValue(pulse: Pulse, t: number): number
	local dt = t - pulse.at
	if dt < 0 then
		return 0
	end
	local attack = CrateOpeningRules.PULSE_ATTACK
	if dt < attack then
		return pulse.power * dt / attack
	end
	local after = dt - attack - pulse.hold
	if after <= 0 then
		return pulse.power
	end
	local k = 1 - after / CrateOpeningRules.PULSE_DECAY
	return if k > 0 then pulse.power * k * k else 0
end

-- Cette méthode permet de donner la plus forte bouffée en cours (toutes, ou celles à rayons si `raysOnly`) lorsque la
-- charge est échantillonnée.
function CrateOpeningRules.pulse(t: number, raysOnly: boolean?): number
	local best = 0
	for _, pulse in CrateOpeningRules.PULSES do
		if not raysOnly or pulse.rays then
			best = math.max(best, pulseValue(pulse, t))
		end
	end
	return best
end

-- Cette méthode permet de donner la tension avant l'explosion (0 → 1 de TENSION_START au temps d'arrêt, puis 1) lorsque
-- la charge est échantillonnée.
function CrateOpeningRules.tension(t: number): number
	local R = CrateOpeningRules
	return clamp01((t - R.TENSION_START) / (R.BURST - R.PAUSE - R.TENSION_START))
end

-- Cette méthode permet de donner l'angle de l'arme (de trois quarts, -SPIN_FROM, elle tourne en ralentissant jusqu'au
-- profil, puis léger balancement) `s` secondes après la colonne lorsque l'arme est posée.
local function spinAngle(s: number, revealAt: number): number
	local from = -CrateOpeningRules.SPIN_FROM
	if s <= 0 then
		return from
	end
	local spinTime = revealAt - CrateOpeningRules.COLUMN + CrateOpeningRules.SPIN_AFTER
	if s < spinTime then
		local u = s / spinTime
		return from * (1 - u) ^ 3
	end
	return CrateOpeningRules.SWAY * math.sin((s - spinTime) * 1.2)
end

-- Cette méthode permet de donner l'état de chaque effet de l'ouverture au temps `t` (s depuis le clic) pour une caisse
-- de rareté `rarityId` lorsqu'une image de l'ouverture est rendue.
function CrateOpeningRules.sample(t: number, rarityId: string?): State
	local R = CrateOpeningRules
	local reveal = R.revealTime(rarityId)
	local charging = t < R.BURST
	local paused = charging and t >= R.BURST - R.PAUSE
	local crackle = if t >= R.CRACKLE_START and charging
		then 0.3 + 0.7 * clamp01((t - R.CRACKLE_START) / (R.BURST - R.CRACKLE_START))
		else 0
	local pulse = if charging then R.pulse(t) else 0
	local tension = if charging then R.tension(t) else 0
	local flash = 0
	if t >= R.BURST and t < R.BURST + R.BURST_FLASH then
		flash = 1 - (t - R.BURST) / R.BURST_FLASH
	end
	if t >= reveal and t < reveal + R.REVEAL_FLASH then
		flash = math.max(flash, 1 - (t - reveal) / R.REVEAL_FLASH)
	end

	-- Colonne : grandit depuis la caisse, puis se resserre et s'atténue derrière la silhouette qui monte
	local column, columnHeight, columnWidth, silhouette, embers = 0, 0, 1, 0, 0
	local s = t - R.COLUMN
	if s >= 0 and t < reveal then
		columnHeight = 1 - (1 - clamp01(s / R.COLUMN_GROW)) ^ 2
		local settle = clamp01((s - R.COLUMN_GROW) / R.COLUMN_SETTLE)
		column = 1 - (1 - R.COLUMN_REST) * settle
		columnWidth = 1 - 0.6 * settle
		silhouette = clamp01(s / R.SILHOUETTE_FADE)
		embers = 1
	elseif t >= reveal then
		columnHeight, columnWidth = 1, 0.4
		column = R.COLUMN_REST * (1 - clamp01((t - reveal) / R.COLUMN_FADE))
	end

	-- Montée de couleur : un palier sur certaines bouffées, la couleur finale dès l'explosion
	local target = R.tierOf(rarityId)
	local tier = 1
	for k = 2, target do
		if t >= R.tierTime(k) then
			tier = k
		end
	end
	if t >= R.BURST then
		tier = target
	end

	local lift = if charging then tension else math.max(0, 1 - (t - R.BURST) / R.LIFT_DROP)
	return {
		push = smooth(t / R.PUSH_TIME),
		shake = if charging and not paused then math.max(crackle * 0.35, pulse, tension) else 0,
		lift = lift,
		glow = if charging then math.max(0.15 + 0.35 * crackle, pulse, tension) else 1,
		-- Chaque bouffée jaillit par la fente ; la bouffée à rayons à pleine force, les autres un peu moins ; rien
		-- pendant le temps d'arrêt
		rays = if charging and not paused then math.max(0.8 * pulse, R.pulse(t, true)) else 0,
		flash = flash,
		lid = clamp01((t - R.LID_START) / R.LID_TIME),
		column = column,
		columnHeight = columnHeight,
		columnWidth = columnWidth,
		embers = embers,
		silhouette = if t >= reveal then 0 else silhouette,
		revealed = t >= reveal,
		rise = smooth(s / R.RISE_TIME),
		spin = spinAngle(s, reveal),
		tier = tier,
	}
end

-- Cette méthode permet de donner le temps où sauter quand le joueur clique pendant l'ouverture : la révélation, ou
-- le temps courant si elle est passée.
function CrateOpeningRules.skip(t: number, rarityId: string?): number
	return math.max(t, CrateOpeningRules.revealTime(rarityId))
end

-- Cette méthode permet de lister les instants de `events` franchis entre deux images (`t0` exclu, `t1` inclus)
-- lorsqu'un effet ponctuel (gerbe d'étincelles) doit partir une seule fois.
function CrateOpeningRules.crossed(events: { number }, t0: number, t1: number): { number }
	local out = {}
	for _, at in events do
		if at > t0 and at <= t1 then
			table.insert(out, at)
		end
	end
	return out
end

-- Cette méthode permet de donner un tremblement déterministe (x, y, roulis entre -1 et 1) au temps `t` lorsque la
-- caisse ou la caméra secoue : sinus de fréquences sans rapport simple, pas de hasard (rendu reproductible).
function CrateOpeningRules.jitter(t: number): (number, number, number)
	local x = 0.6 * math.sin(t * 47.3) + 0.4 * math.sin(t * 91.7 + 1.3)
	local y = 0.6 * math.sin(t * 53.9 + 0.7) + 0.4 * math.sin(t * 83.1 + 2.1)
	local r = 0.6 * math.sin(t * 39.7 + 2.9) + 0.4 * math.sin(t * 77.3 + 0.4)
	return x, y, r
end

return CrateOpeningRules
