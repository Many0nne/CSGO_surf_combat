-- Garde commune des remotes client → serveur (#170, docs/anticheat.md « Remotes ») : règles pures, sans service ni
-- workspace, testées sous Lune (tests/specs/RemoteGuard.spec.luau).
-- - Débit : un seau à jetons par joueur et par remote (rate jetons/s, plafond burst). Un appel sans jeton est ignoré.
-- - Types : chaque argument est vérifié par un contrôle simple (Instance, Vector3 fini, nombre fini, chaîne bornée,
--   valeur d'énumération, table). Un type que notre client n'envoie jamais est une violation forte (CheatLog).
-- - Instance absente (nil) : ignorée sans violation. Une Instance qui n'existe que chez le client (corps en ragdoll
--   cloné localement, décor du menu) arrive en nil au serveur : un client honnête peut donc en envoyer.
-- Le branchement (journal, kick) est fait par CheatLog.admit ; RULES décrit chaque remote écouté par le serveur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathRules = require(ReplicatedStorage.Shared.MathRules)
local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local RemoteGuard = {}

-- Résultat d'un contrôle : "ok" (appel accepté), "rate" (débit dépassé), "malformed" (type impossible pour notre
-- client), "missing" (Instance absente, ignorée sans violation), "norule" (remote absent de RULES : bug du serveur,
-- refusé sans violation).
export type Verdict = "ok" | "rate" | "malformed" | "missing" | "norule"
-- Un contrôle d'argument renvoie le verdict et, s'il échoue, une raison lisible.
export type Check = (value: any) -> (Verdict, string?)
export type Rule = { rate: number, burst: number, args: { Check } }
export type Bucket = { tokens: number, at: number }
export type Guard = {
	rules: { [string]: Rule },
	buckets: { [any]: { [string]: Bucket } },
	check: (self: Guard, key: any, remoteName: string, now: number, ...any) -> (Verdict, string?),
	forget: (self: Guard, key: any) -> (),
}

-- ── Seau à jetons ────────────────────────────────────────────────────────────

-- Cette méthode permet de créer un seau plein lorsqu'un joueur appelle un remote pour la première fois.
function RemoteGuard.newBucket(burst: number, now: number): Bucket
	return { tokens = burst, at = now }
end

-- Cette méthode permet de consommer un jeton lorsqu'un appel arrive : le seau se remplit de rate jetons par seconde
-- écoulée, plafonné à burst ; renvoie false (seau intact) s'il manque un jeton.
function RemoteGuard.take(bucket: Bucket, rate: number, burst: number, now: number): boolean
	local elapsed = math.max(now - bucket.at, 0)
	bucket.tokens = math.min(burst, bucket.tokens + elapsed * rate)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- ── Contrôles de type ────────────────────────────────────────────────────────

-- Cette méthode permet de décrire le type reçu lorsqu'un contrôle échoue (raison du journal).
local function describe(value: any): string
	return typeof(value)
end

-- Cette méthode permet de construire le contrôle « Instance » lorsqu'un remote reçoit un personnage ou une pièce ;
-- nil est « missing » (Instance propre au client), tout autre type est impossible.
function RemoteGuard.instance(): Check
	return function(value)
		if value == nil then
			return "missing", "Instance absente"
		end
		if typeof(value) ~= "Instance" then
			return "malformed", "Instance attendue, reçu " .. describe(value)
		end
		return "ok"
	end
end

-- Cette méthode permet de construire le contrôle « Vector3 fini » lorsqu'un remote reçoit une position.
function RemoteGuard.vector3(): Check
	return function(value)
		if typeof(value) ~= "Vector3" then
			return "malformed", "Vector3 attendu, reçu " .. describe(value)
		end
		if not MathRules.isFiniteVector3(value) then
			return "malformed", "Vector3 non fini"
		end
		return "ok"
	end
end

-- Cette méthode permet de construire le contrôle « nombre fini » lorsqu'un remote reçoit un angle ou une durée.
function RemoteGuard.number(): Check
	return function(value)
		if not MathRules.isFinite(value) then
			return "malformed", "nombre fini attendu, reçu " .. describe(value)
		end
		return "ok"
	end
end

-- Cette méthode permet de construire le contrôle « booléen » lorsqu'un remote reçoit un état (accroupi, #213).
function RemoteGuard.boolean(): Check
	return function(value)
		if type(value) ~= "boolean" then
			return "malformed", "booléen attendu, reçu " .. describe(value)
		end
		return "ok"
	end
end

-- Cette méthode permet de construire le contrôle « chaîne d'au plus maxLen octets » lorsqu'un remote reçoit du texte.
function RemoteGuard.string(maxLen: number): Check
	return function(value)
		if type(value) ~= "string" then
			return "malformed", "string attendue, reçu " .. describe(value)
		end
		if #value > maxLen then
			return "malformed", string.format("string de %d octets (max %d)", #value, maxLen)
		end
		return "ok"
	end
end

-- Cette méthode permet de construire le contrôle « une des valeurs » lorsqu'un remote reçoit un nom d'action.
function RemoteGuard.enum(values: { string }): Check
	local allowed: { [string]: boolean } = {}
	for _, v in values do
		allowed[v] = true
	end
	return function(value)
		if type(value) ~= "string" or not allowed[value] then
			return "malformed",
				"valeur inconnue : " .. (if type(value) == "string" then string.sub(value, 1, 40) else describe(value))
		end
		return "ok"
	end
end

-- Cette méthode permet de construire le contrôle « table » lorsqu'un remote reçoit une structure assainie ensuite.
function RemoteGuard.table(): Check
	return function(value)
		if type(value) ~= "table" then
			return "malformed", "table attendue, reçu " .. describe(value)
		end
		return "ok"
	end
end

-- Cette méthode permet de vérifier les arguments d'un appel dans l'ordre lorsqu'il a passé le débit ; le premier
-- contrôle en échec donne le verdict. Les arguments en trop sont ignorés (sans effet sur les handlers).
function RemoteGuard.checkArgs(checks: { Check }, args: { [number]: any }): (Verdict, string?)
	for i, check in checks do
		local verdict, reason = check(args[i])
		if verdict ~= "ok" then
			return verdict, string.format("arg %d : %s", i, reason or "?")
		end
	end
	return "ok"
end

-- ── Règles des remotes ───────────────────────────────────────────────────────

-- Longueur maximale d'un feedback accepté par la garde : le client coupe à 500 octets (MAX_CHARS, local de
-- src/client/ui/FeedbackScreen.luau, à garder sous cette borne) et le serveur répond au-delà ; marge pour qu'un client
-- honnête ne soit jamais pris pour un tricheur.
RemoteGuard.FEEDBACK_MAX_BYTES = 1000

-- Débits calibrés pour qu'un client honnête ne les atteigne jamais (rafale réseau comprise), cf. docs/anticheat.md :
-- - MeleeDamage : couteau 0,4 s mini (2,5/s) ; HitscanDamage et ShotFired : AWP 1,46 s (0,7/s) ; WeaponAction : un Shoot par coup
--   de couteau (#215 : plus par tir), un Reload par chargeur ; CharacterSync : 20 Hz, paquets regroupés après une coupure réseau ;
--   RequestSpawn : clic du menu ; LeaveRound : clic MENU PRINCIPAL du menu en partie ;
--   SendFeedback : clic ENVOYER ; SaveSettings : 1 envoi par seconde au plus (LocalSettings) ; GetSettings : une
--   demande au démarrage du client.
-- Une arme plus rapide (automatique) demandera de relever HitscanDamage, ShotFired et WeaponAction.
local N = NetworkProtocol.Names
RemoteGuard.RULES = {
	-- Cible, type d'attaque, instant du coup (#214, horloge serveur comme shotTime, borné ensuite par le ping)
	[N.MELEE_DAMAGE] = {
		rate = 5,
		burst = 5,
		args = {
			RemoteGuard.instance(),
			RemoteGuard.enum({ WeaponConfig.AttackKind.PRIMARY, WeaponConfig.AttackKind.SECONDARY }),
			RemoteGuard.number(),
		},
	},
	-- Cible, partie touchée, origine, direction, point d'impact, instant du tir (#174, contrôlés ensuite par ShotRules)
	[N.HITSCAN_DAMAGE] = {
		rate = 5,
		burst = 5,
		args = {
			RemoteGuard.instance(),
			RemoteGuard.instance(),
			RemoteGuard.vector3(),
			RemoteGuard.vector3(),
			RemoteGuard.vector3(),
			RemoteGuard.number(),
		},
	},
	-- Tir à relayer aux autres clients (#156) : origine, direction (cadence de l'arme vérifiée ensuite, ShotRelayRules),
	-- instant du tir (#216 : la touche s'y rattache, même valeur que dans HitscanDamage)
	[N.SHOT_FIRED] = {
		rate = 5,
		burst = 5,
		args = { RemoteGuard.vector3(), RemoteGuard.vector3(), RemoteGuard.number() },
	},
	[N.WEAPON_ACTION] = { rate = 8, burst = 8, args = { RemoteGuard.enum({ "Shoot", "Reload" }) } },
	-- Position, cap, numéro de correction, accroupi (#213)
	[N.CHARACTER_SYNC] = {
		rate = 40,
		burst = 60,
		args = { RemoteGuard.vector3(), RemoteGuard.number(), RemoteGuard.number(), RemoteGuard.boolean() },
	},
	[N.REQUEST_SPAWN] = { rate = 1, burst = 3, args = {} },
	[N.LEAVE_ROUND] = { rate = 1, burst = 3, args = {} },
	[N.SEND_FEEDBACK] = { rate = 0.5, burst = 3, args = { RemoteGuard.string(RemoteGuard.FEEDBACK_MAX_BYTES) } },
	[N.SAVE_SETTINGS] = { rate = 2, burst = 5, args = { RemoteGuard.table() } },
	[N.GET_SETTINGS] = { rate = 0.2, burst = 3, args = {} },
} :: { [string]: Rule }

-- ── Garde ────────────────────────────────────────────────────────────────────

-- Cette méthode permet de contrôler un appel lorsqu'il arrive : débit d'abord (un appel en trop n'est pas analysé),
-- puis types. key désigne l'appelant (le Player) ; un remote absent des règles est refusé en « norule ».
local function check(self: Guard, key: any, remoteName: string, now: number, ...: any): (Verdict, string?)
	local rule = self.rules[remoteName]
	if not rule then
		return "norule", "remote sans règle : " .. tostring(remoteName)
	end
	local perKey = self.buckets[key]
	if not perKey then
		perKey = {}
		self.buckets[key] = perKey
	end
	local bucket = perKey[remoteName]
	if not bucket then
		bucket = RemoteGuard.newBucket(rule.burst, now)
		perKey[remoteName] = bucket
	end
	if not RemoteGuard.take(bucket, rule.rate, rule.burst, now) then
		return "rate", string.format("plus de %g appels/s (rafale %d)", rule.rate, rule.burst)
	end
	return RemoteGuard.checkArgs(rule.args, table.pack(...))
end

-- Cette méthode permet d'oublier les seaux d'un joueur lorsqu'il quitte le serveur.
local function forget(self: Guard, key: any)
	self.buckets[key] = nil
end

-- Cette méthode permet de créer une garde avec ses seaux lorsque le serveur démarre (RULES par défaut).
function RemoteGuard.new(rules: { [string]: Rule }?): Guard
	return {
		rules = rules or RemoteGuard.RULES,
		buckets = {},
		check = check,
		forget = forget,
	}
end

return RemoteGuard
