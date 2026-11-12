-- CasingRules.luau
-- Douille éjectée à l'ouverture de la culasse (#237) : règles pures du client (CasingEjection), testées sous Lune
-- (tests/specs/CasingRules.spec.luau).
-- Point d'éjection : l'Attachment EjectPort de la poignée (Handle) de l'arme, à la fenêtre d'éjection. Son repère :
-- +X vers l'extérieur (côté droit de l'arme, par où sort la douille), +Y vers le haut, +Z vers l'arrière (le tireur).
-- La douille part de ce point avec une vitesse et une rotation tirées dans des fourchettes, suit un arc balistique dans
-- le monde (elle hérite de la vitesse du tireur, comme dans CS) puis disparaît au bout de LIFETIME.
-- En 1re personne, elle part au marqueur MARKER de l'animation Shoot ; chez les autres (arme 3P, joueurs et bots), au
-- tir relayé (ShotFired) plus le CasingEjectDelay de l'arme (WeaponConfig), l'instant de ce marqueur dans la piste.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)

local CasingRules = {}

-- Point d'éjection dans le modèle de l'arme (viewmodel ou 3P, qui clone les pièces du viewmodel avec leurs enfants).
-- Une arme sans ce chemin n'éjecte rien.
CasingRules.PORT_PATH = { "Handle", "EjectPort" }
-- Marqueur de l'animation Shoot posé au recul de la culasse (assets/awp_viewmodel/build_anims.py, spec_shoot).
CasingRules.MARKER = "Eject"

-- Douille à l'échelle du viewmodel (studs ; l'arme 3P la réduit avec son échelle) : cylindre couché le long de
-- l'arme, laiton.
CasingRules.LENGTH = 0.62
CasingRules.DIAMETER = 0.11
CasingRules.COLOR_RGB = { 214, 170, 84 }

-- Vitesse de départ (studs/s, échelle du viewmodel) dans le repère de l'EjectPort : vers la droite, vers le haut,
-- vers l'arrière. Chaque composante non nulle varie de ± SPREAD (fraction) d'un tir à l'autre. Référence CS2 (awp showcase.mp4,
-- 20,233 à 20,367 s) : la douille monte vers la droite et sort par le bord droit vers 30 % de la hauteur en 0,15 s,
-- sa montée freinant déjà. Valeurs ajustées sur ces déplacements à l'écran (rendu de Shoot au FOV 90, 16:9) : l'arme
-- est penchée pendant le cycle de culasse, le haut de l'EjectPort pointe vers le haut et la droite de l'écran.
CasingRules.EJECT_VELOCITY = { 12, 24, 0 }
CasingRules.SPREAD = 0.15
-- Rotation (rad/s) : surtout bout sur bout autour de l'axe vertical de l'EjectPort (± SPREAD), un peu de roulis fixe
-- sur l'axe de la douille.
CasingRules.SPIN_YAW = 22
CasingRules.SPIN_ROLL = 6
-- Gravité (studs/s², échelle du viewmodel), plus forte que celle du monde réel à cette échelle pour que la douille
-- retombe hors du cadre avant de disparaître.
CasingRules.GRAVITY = 120
-- Durée de vie (s) : la douille disparaît ensuite (retour au pool).
CasingRules.LIFETIME = 0.8
-- Douilles en vol au plus. Une douille du joueur local prend la plus ancienne si tout est pris ; une douille d'un
-- autre n'en prend qu'une libre (elle ne chasse jamais celle qu'on voit devant soi).
CasingRules.POOL_SIZE = 8
-- Nom des pièces de douille (repérables en Studio, comptées par la vérification « aucune instance restante »).
CasingRules.INSTANCE_NAME = "ShotCasing"
-- Tir relayé : la vitesse du tireur se déduit du déplacement moyen de son arme 3P entre le tir et l'éjection
-- (approximation : un tireur qui freine pendant ce délai donne une vitesse moyenne). Au-delà de la vitesse maximale
-- d'un joueur (plus une marge, studs/s), c'est un saut (réapparition, téléportation) : la douille n'hérite de rien.
CasingRules.MAX_INHERITED_SPEED = MovementConfig.MAX_SPEED_SERVER + 50
-- Tir relayé à plus de cette distance (studs) de notre caméra : pas de douille (quelques pixels, invisible).
CasingRules.MAX_REMOTE_DISTANCE = 150

-- Cette méthode permet de tirer une valeur autour de base lorsqu'une douille part : u ∈ [0, 1] donne base ± SPREAD.
local function jitter(base: number, u: number): number
	return base * (1 + (u * 2 - 1) * CasingRules.SPREAD)
end

-- État de vol d'une douille : CFrame de départ (axe de la douille sur X, celui d'une Part cylindrique), vitesse et
-- rotation (vecteur axe × rad/s) dans le monde, gravité à son échelle.
export type Flight = {
	start: CFrame,
	velocity: Vector3,
	spin: Vector3,
	gravity: number,
}

-- Cette méthode permet de préparer le vol d'une douille lorsqu'elle sort de l'EjectPort (CFrame monde port, échelle
-- de l'arme, vitesse du tireur), rolls étant quatre tirages dans [0, 1] (vitesse droite, haut, arrière, rotation).
function CasingRules.launch(port: CFrame, scale: number, inherited: Vector3, rolls: { number }): Flight
	local v = CasingRules.EJECT_VELOCITY
	local localVelocity = Vector3.new(jitter(v[1], rolls[1]), jitter(v[2], rolls[2]), jitter(v[3], rolls[3]))
	local velocity = port:VectorToWorldSpace(localVelocity) * scale + inherited
	local spinLocal = Vector3.new(0, jitter(CasingRules.SPIN_YAW, rolls[4]), CasingRules.SPIN_ROLL)
	-- axe de la douille (Z de l'EjectPort, le long de l'arme) sur X, l'axe d'une Part cylindrique
	local start = port * CFrame.Angles(0, math.pi / 2, 0)
	return {
		start = start,
		velocity = velocity,
		spin = port:VectorToWorldSpace(spinLocal),
		gravity = CasingRules.GRAVITY * scale,
	}
end

-- Cette méthode permet de placer une douille en vol lorsqu'une frame passe : arc balistique depuis son départ, et
-- rotation constante autour de son axe de rotation (monde), t secondes après l'éjection.
function CasingRules.cframeAt(flight: Flight, t: number): CFrame
	local p0 = flight.start.Position
	local position = p0 + flight.velocity * t - Vector3.new(0, 0.5 * flight.gravity * t * t, 0)
	local rate = flight.spin.Magnitude
	local rotation = flight.start - p0
	if rate > 0 then
		rotation = CFrame.fromAxisAngle(flight.spin / rate, rate * t) * rotation
	end
	return rotation + position
end

-- Cette méthode permet de savoir si une douille a fini sa vie lorsqu'une frame passe (elle retourne au pool).
function CasingRules.isExpired(t: number): boolean
	return t >= CasingRules.LIFETIME
end

-- Cette méthode permet d'estimer la vitesse d'un tireur distant lorsque sa douille part : déplacement de son arme
-- entre le tir relayé et l'éjection ; zéro si la durée est nulle ou si le déplacement est un saut.
function CasingRules.inheritedVelocity(from: Vector3, to: Vector3, elapsed: number): Vector3
	if elapsed <= 0 then
		return Vector3.zero
	end
	local velocity = (to - from) / elapsed
	if velocity.Magnitude > CasingRules.MAX_INHERITED_SPEED then
		return Vector3.zero
	end
	return velocity
end

-- Cette méthode permet de savoir si la douille d'un tir relayé vaut d'être montrée lorsqu'elle part : son arme est
-- assez près de notre caméra pour qu'on la voie.
function CasingRules.isNearCamera(port: Vector3, camera: Vector3): boolean
	return (port - camera).Magnitude <= CasingRules.MAX_REMOTE_DISTANCE
end

-- Cette méthode permet de choisir l'emplacement du pool d'une douille lorsqu'elle part (born[i] : instant d'éjection,
-- nil si libre) : un libre d'abord, sinon le plus ancien si evict est vrai, sinon nil (pas de douille).
function CasingRules.pickSlot(born: { [number]: number? }, size: number, evict: boolean): number?
	local oldest, oldestTime = 1, math.huge
	for i = 1, size do
		local b = born[i]
		if b == nil then
			return i
		end
		if b < oldestTime then
			oldest, oldestTime = i, b
		end
	end
	return if evict then oldest else nil
end

return CasingRules
