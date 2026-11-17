-- Clip de la partie (#499), côté serveur : la meilleure action de la manche est rejouée chez tous à la fin, en 1re
-- personne du tireur, à partir de données (aucune vidéo, rien d'envoyé en continu).
-- - Pendant la manche : piste de chaque participant (positions acceptées par CharacterSync, joueurs et bots) et tirs
--   acceptés gardés dans des tampons de taille fixe (HighlightClipRules), sans changer le rembobinage (#173).
-- - À chaque kill crédité : notation (HighlightRules). Un kill qui bat le record de la manche est figé POST_ROLL plus
--   tard : fenêtre des pistes copiée, apparence des personnages gardée (clone sans scripts, même si le joueur part), et
--   tampon caméra demandé au client du tireur (remote HighlightPov), recalé sur l'historique serveur ; refusé, absent
--   ou tireur bot : POV reconstruit depuis la position, le cap et les tirs serveur (tangage dégradé).
-- - Fin de manche (RoundManager.endRound) : `take` rend le clip retenu (diffusé dans RoundResult) et publie les
--   figurants dans ReplicatedStorage ; `reset` (retour à idle) oublie tout.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local HighlightClipRules = require(ReplicatedStorage.Shared.HighlightClipRules)
local MathRules = require(ReplicatedStorage.Shared.MathRules)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)
local CheatLog = require(script.Parent.CheatLog)
local HighlightRules = require(script.Parent.HighlightRules)
local Participants = require(script.Parent.Participants)

type Participant = Participants.Participant
type Kill = HighlightRules.Kill

-- Dossier des figurants publiés pour la lecture (ReplicatedStorage), un modèle par participant nommé par son id.
local ACTORS_FOLDER = "HighlightActors"
-- Attente maximale (s) du tampon caméra du tireur ; au-delà, POV reconstruit par le serveur.
local POV_TIMEOUT = 3
-- Écart (s) entre le dernier coup reçu et la mort au-delà duquel la mort est une chute provoquée (exclue).
local FALL_DELAY = 0.5
-- Âge maximal (s) du flick d'une touche pour qu'il compte dans le kill qu'elle donne.
local FLICK_MAX_AGE = 0.5

export type Deps = {
	enabled: boolean,
	povRemote: RemoteEvent,
	isActive: () -> boolean,
	-- Outil en main d'un participant (arme du clip), skin équipé d'un outil (viewmodel du clip), sol sous une position
	toolOf: (Participant) -> Tool?,
	skinOf: (Participant, string) -> string?,
	isAirborne: (Vector3) -> boolean,
}

type Meta = { direction: Vector3?, tool: string?, weapon: string, skinId: string? }
type Pending = { id: number, start: number, stop: number, done: (rows: { HighlightClipRules.CameraRow }?) -> () }

local HighlightService = {}

-- Hauteur sondée (studs) sous la racine pour décider qu'un personnage est en l'air (racine ~3 studs au-dessus des pieds),
-- lue par la sonde de init.server (deps.isAirborne).
HighlightService.AIR_PROBE = 4.5

local deps: Deps? = nil
local tracks: { [number]: HighlightClipRules.Track } = {}
local shots: { [number]: HighlightClipRules.ShotRing } = {}
-- Personnage → id de participant (posé à l'apparition), pour les positions relayées par CharacterSync
local owners: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local names: { [number]: string } = {}
local kills: { Kill } = {}
local metas: { [Kill]: Meta } = {}
local streaks: { [number]: number } = {}
local flicks: { [number]: { at: number, flick: boolean } } = {}
local bestScore: number? = nil
-- Numéro du record en cours de figeage : un record plus récent périme le précédent
local token = 0
local clip: HighlightClipRules.Clip? = nil
local clipActors: { number } = {}
local pending: { [Player]: Pending } = {}
local nextPovId = 0
local appearances: Folder? = nil -- ServerStorage : apparence de chaque participant de la manche
local published: Folder? = nil -- ReplicatedStorage : figurants du clip pendant le résultat

-- Cette méthode permet d'écrire une ligne préfixée dans la sortie de Studio lorsque le clip avance (rien en jeu publié).
local function log(text: string)
	if RunService:IsStudio() then
		print("[Highlight] " .. text)
	end
end

-- Cette méthode permet de retrouver (ou créer) le dossier des apparences lorsqu'un personnage est gardé.
local function appearanceFolder(): Folder
	local folder = appearances
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "HighlightAppearances"
	created.Parent = ServerStorage
	appearances = created
	return created
end

-- Cette méthode permet de garder l'apparence d'un participant (clone du personnage sans scripts, outils, bouclier ni
-- sons hors ceux de l'arme 3P, tirés pendant le rejeu ; humanoïde en vie, racine seule ancrée) lorsqu'il meurt ou
-- qu'un record est figé ; une fois par manche.
local function keepAppearance(id: number, char: Model?)
	local folder = appearanceFolder()
	if not char or folder:FindFirstChild(tostring(id)) then
		return
	end
	local wasArchivable = char.Archivable
	char.Archivable = true
	local ok, copy = pcall(char.Clone, char)
	char.Archivable = wasArchivable
	if not ok or not copy then
		return
	end
	local gun = copy:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
	for _, inst in copy:GetDescendants() do
		if
			inst:IsA("LuaSourceContainer")
			or inst:IsA("Tool")
			or inst:IsA("ForceField")
			or (inst:IsA("Sound") and not (gun and inst:IsDescendantOf(gun)))
			or inst:IsA("BillboardGui")
		then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.Anchored = inst.Name == "HumanoidRootPart"
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Copié à la mort : remis en vie, sinon le figurant se désarticule chez le client
		humanoid.BreakJointsOnDeath = false
		humanoid.Health = humanoid.MaxHealth
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	copy.Name = tostring(id)
	copy.Parent = folder
end

-- Cette méthode permet de lire la position de la racine d'un personnage lorsqu'un kill est noté (nil sans racine).
local function rootOf(char: Model?): Vector3?
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Cette méthode permet de mesurer la vitesse horizontale récente d'un participant (studs/s) sur sa piste lorsqu'un kill
-- est noté ; 0 sans deux positions récentes.
local function speedOf(id: number, now: number): number
	local track = tracks[id]
	if not track then
		return 0
	end
	local a = HighlightClipRules.trackAt(track, now - 0.15)
	local b = HighlightClipRules.trackAt(track, now)
	if not a or not b then
		return 0
	end
	return MathRules.horizontalLength(b - a) / 0.15
end

-- ── Pistes et tirs ─────────────────────────────────────────────────────────

-- Cette méthode permet d'associer le personnage d'un participant à son id lorsqu'il apparaît (positions relayées par
-- CharacterSync, qui ne connaît que le personnage).
function HighlightService.track(participant: Participant, char: Model)
	owners[char] = participant.id
	names[participant.id] = participant.name
end

-- Cette méthode permet d'ajouter une position acceptée à la piste de son participant lorsque CharacterSync la pose ;
-- seulement en manche active (aucun coût au menu, à l'entraînement ni pendant le résultat).
function HighlightService.recordPosition(char: Model, pos: Vector3, yaw: number, stamp: number)
	local d = deps
	if not d or not d.enabled or not d.isActive() then
		return
	end
	local id = owners[char]
	if not id then
		return
	end
	local track = tracks[id]
	if not track then
		track = HighlightClipRules.newTrack()
		tracks[id] = track
	end
	HighlightClipRules.recordTrack(track, stamp, pos, yaw)
end

-- Cette méthode permet de retenir un tir accepté (instant serveur ; `aimed` faux pour un coup de couteau, dont la
-- direction est celle de la racine) lorsqu'il est relayé ou porté.
function HighlightService.noteShot(participant: Participant, direction: Vector3, shotTime: number?, aimed: boolean?)
	local d = deps
	if not d or not d.enabled or not d.isActive() or not MathRules.isFiniteVector3(direction) then
		return
	end
	local now = workspace:GetServerTimeNow()
	-- Instant du tir annoncé par le client (celui de sa caméra), s'il est plausible ; sinon l'arrivée
	local t = if MathRules.isFinite(shotTime) and math.abs((shotTime :: number) - now) < 1
		then shotTime :: number
		else now
	local ring = shots[participant.id]
	if not ring then
		ring = HighlightClipRules.newShotRing()
		shots[participant.id] = ring
	end
	HighlightClipRules.pushShot(ring, t, if direction.Magnitude > 1e-6 then direction.Unit else direction, aimed)
end

-- Cette méthode permet de retenir si la dernière touche d'un participant suivait un flick (AimStats) lorsqu'elle est
-- comptée ; lu par le kill qu'elle donne.
function HighlightService.noteFlick(participant: Participant, flick: boolean)
	flicks[participant.id] = { at = os.clock(), flick = flick }
end

-- Cette méthode permet de noter la mort d'un participant (série remise à zéro, apparence gardée tant que le personnage
-- existe) lorsqu'il meurt, avant la destruction de son corps.
function HighlightService.onDeath(participant: Participant, char: Model)
	local d = deps
	if not d or not d.enabled or not d.isActive() then
		return
	end
	streaks[participant.id] = 0
	keepAppearance(participant.id, char)
end

-- ── Figeage d'un record ────────────────────────────────────────────────────

-- Cette méthode permet de demander au client du tireur sa caméra sur [start, stop] lorsqu'un record est figé ; `done`
-- reçoit les échantillons décodés, ou nil (pas de réponse dans POV_TIMEOUT, réponse illisible, joueur parti).
local function requestPov(player: Player, start: number, stop: number, done: (rows: { any }?) -> ())
	local d = deps :: Deps
	nextPovId += 1
	local id = nextPovId
	local previous = pending[player]
	if previous then
		previous.done(nil)
	end
	pending[player] = { id = id, start = start, stop = stop, done = done }
	d.povRemote:FireClient(player, id, start, stop)
	task.delay(POV_TIMEOUT, function()
		local current = pending[player]
		if current and current.id == id then
			pending[player] = nil
			log("caméra du tireur sans réponse : POV reconstruit")
			done(nil)
		end
	end)
end

-- Cette méthode permet de recevoir la caméra renvoyée par un client lorsqu'elle arrive : seulement en réponse à la
-- demande en attente (même numéro), décodée et bornée ; une série illisible est journalisée (gravité faible).
local function onPovReceived(player: Player, id: any, text: any)
	local current = pending[player]
	if not current or current.id ~= id then
		return
	end
	pending[player] = nil
	local rows, why =
		HighlightClipRules.decodeSeries(text, HighlightClipRules.CAMERA_SCALES, HighlightClipRules.CAMERA_CAPACITY + 2)
	if not rows then
		CheatLog.report(
			Participants.fromPlayer(player),
			CheatLog.Category.REMOTE_ARGS,
			CheatLog.Severity.LOW,
			"caméra du clip illisible : " .. tostring(why),
			"highlightPov"
		)
		current.done(nil)
		return
	end
	local camera: { HighlightClipRules.CameraRow } = {}
	for _, row in rows do
		if row then
			table.insert(camera, row :: { number })
		end
	end
	current.done(camera)
end

-- Cette méthode permet de figer le clip d'un record lorsque sa fenêtre est passée : pistes de tous les participants,
-- tirs, kills de la chaîne, apparences, puis caméra du tireur (demandée à son client, recalée) ou POV serveur. Le clip
-- n'est retenu que si aucun record plus récent n'est arrivé entre-temps (`myToken`).
local function freeze(myToken: number, chain: { Kill }, killer: Participant)
	local d = deps
	if myToken ~= token or not d or not d.isActive() then
		return
	end
	local startedAt = os.clock()
	local start, stop = HighlightRules.window(chain)
	local last = chain[#chain]
	local meta = metas[last]

	-- Apparences des participants encore en jeu (les morts ont été gardés à leur mort)
	for _, participant in Participants.all() do
		local char = Participants.characterOf(participant)
		if char then
			keepAppearance(participant.id, char)
		end
	end

	local actorCount = HighlightClipRules.rowCount(start, stop, HighlightClipRules.ACTOR_HZ)
	local actors = {}
	local actorIds: { number } = {}
	local folder = appearanceFolder()
	for id, track in tracks do
		if id == killer.id or not folder:FindFirstChild(tostring(id)) then
			continue
		end
		local rows, any = HighlightClipRules.trackRows(track, start, actorCount, HighlightClipRules.ACTOR_HZ)
		if any then
			table.insert(actors, {
				id = id,
				name = names[id] or "?",
				track = HighlightClipRules.encodeSeries(rows, HighlightClipRules.ACTOR_SCALES),
			})
			table.insert(actorIds, id)
		end
	end

	local clipShots = {}
	for id, ring in shots do
		for _, shot in HighlightClipRules.shotsIn(ring, start, stop) do
			-- Direction des tirs visés : rayon de la balle rejoué ; coup de couteau (direction de la racine) : aucun rayon
			table.insert(clipShots, { t = shot.t - start, id = id, dir = if shot.aimed then shot.dir else nil })
		end
	end
	local clipKills = {}
	for _, kill in chain do
		local each = metas[kill]
		table.insert(clipKills, {
			t = kill.t - start,
			victimId = kill.victimId,
			headshot = kill.headshot,
			direction = each and each.direction,
		})
	end

	local killerTrack = tracks[killer.id]
	local killerShots = if shots[killer.id] then HighlightClipRules.shotsIn(shots[killer.id], start, stop) else {}
	-- Cette méthode permet de lire la position et le cap du tireur sur sa piste lorsque son POV est recalé ou reconstruit.
	local function killerAt(t: number): (Vector3?, number?)
		if not killerTrack then
			return nil, nil
		end
		return HighlightClipRules.trackAt(killerTrack, t)
	end

	-- Cette méthode permet de terminer le clip avec la caméra du client (recalée) ou sans (POV serveur) lorsqu'elle est
	-- connue ; ignoré si un record plus récent a pris la place entre-temps.
	local function finish(camera: { any }?)
		if myToken ~= token then
			return
		end
		local trusted = camera
		if camera then
			local ok, why = HighlightClipRules.checkPov(camera, start, function(t)
				return (killerAt(t))
			end, killerShots)
			if not ok then
				trusted = nil
				log("caméra du tireur refusée (" .. tostring(why) .. ") : POV reconstruit")
				if killer.player then
					CheatLog.report(
						killer,
						CheatLog.Category.AIM,
						CheatLog.Severity.LOW,
						"caméra du clip écartée : " .. tostring(why),
						"highlightPov"
					)
				end
			end
		end
		local count = HighlightClipRules.rowCount(start, stop, HighlightClipRules.POV_HZ)
		local pov = HighlightClipRules.buildPov(start, count, trusted, killerAt, killerShots)
		clip = {
			version = HighlightClipRules.VERSION,
			duration = stop - start,
			killerId = killer.id,
			killerName = killer.name,
			weapon = meta and meta.weapon or "",
			tool = meta and meta.tool,
			skinId = meta and meta.skinId,
			degraded = trusted == nil,
			pov = HighlightClipRules.encodeSeries(pov, HighlightClipRules.POV_SCALES),
			actors = actors,
			shots = clipShots,
			kills = clipKills,
		} :: any
		clipActors = actorIds
		log(
			string.format(
				"clip retenu : %s, %d kill(s), %.1f s, %d figurant(s), POV %s, figé en %.1f ms",
				killer.name,
				#chain,
				stop - start,
				#actors,
				if trusted then "du client" else "serveur",
				(os.clock() - startedAt) * 1000
			)
		)
	end

	local player = killer.player
	if player and player.Parent == Players then
		requestPov(player, start, stop, finish)
	else
		finish(nil)
	end
end

-- Cette méthode permet de noter un kill crédité lorsqu'il est compté (RoundManager) : contexte lu sur les personnages
-- (distance, en l'air, vitesse, arme), série et flick ; s'il bat le record de la manche, le clip est figé POST_ROLL
-- plus tard (fin de la fenêtre).
function HighlightService.onKill(
	victim: Participant,
	killer: Participant,
	hit: { weapon: string?, headshot: boolean, at: number? }
)
	local d = deps
	if not d or not d.enabled or not d.isActive() then
		return
	end
	local now = workspace:GetServerTimeNow()
	local victimPos = rootOf(Participants.characterOf(victim))
	local killerChar = Participants.characterOf(killer)
	local killerPos = rootOf(killerChar)
	local streak = (streaks[killer.id] or 0) + 1
	streaks[killer.id] = streak
	local flick = flicks[killer.id]
	local weapon = hit.weapon or ""
	local config = WeaponConfig.Weapons[weapon]
	local tool = d.toolOf(killer)
	local kill: Kill = {
		killerId = killer.id,
		victimId = victim.id,
		t = now,
		headshot = hit.headshot,
		distance = if victimPos and killerPos then (victimPos - killerPos).Magnitude else 0,
		flick = flick ~= nil and flick.flick and os.clock() - flick.at <= FLICK_MAX_AGE,
		speed = speedOf(killer.id, now),
		killerAirborne = killerPos ~= nil and d.isAirborne(killerPos),
		victimAirborne = victimPos ~= nil and d.isAirborne(victimPos),
		-- AWP sans lunette : le serveur ne connaît pas l'état de la lunette, seul le couteau compte
		hardWeapon = config ~= nil and config.IsMelee == true,
		streak = streak,
		fall = hit.at == nil or os.clock() - hit.at > FALL_DELAY,
	}
	local recent = kills
	local score = HighlightRules.score(kill, recent)
	local chain = HighlightRules.chain(recent, kill)
	table.insert(kills, kill)
	metas[kill] = {
		direction = if victimPos
				and killerPos
				and (victimPos - killerPos).Magnitude > 0.01
			then (victimPos - killerPos).Unit
			else nil,
		weapon = weapon,
		tool = tool and tool.Name,
		skinId = if tool then d.skinOf(killer, tool.Name) else nil,
	}
	keepAppearance(victim.id, Participants.characterOf(victim))
	if not HighlightRules.beats(score, bestScore) then
		return
	end
	bestScore = score
	token += 1
	log(
		string.format(
			"record : %s sur %s, %.1f points (%d kill(s) enchaînés)",
			killer.name,
			victim.name,
			score :: number,
			#chain
		)
	)
	task.delay(HighlightRules.POST_ROLL, freeze, token, chain, killer)
end

-- ── Fin de manche ──────────────────────────────────────────────────────────

-- Cette méthode permet de rendre le clip retenu de la manche lorsqu'elle se termine (nil sans kill valide) et de publier
-- ses figurants dans ReplicatedStorage pour la lecture des clients ; un record encore en cours de figeage est perdu.
function HighlightService.take(): HighlightClipRules.Clip?
	token += 1
	local retained = clip
	if not retained then
		return nil
	end
	if published then
		published:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = ACTORS_FOLDER
	local source = appearanceFolder()
	for _, id in clipActors do
		local model = source:FindFirstChild(tostring(id))
		if model then
			model:Clone().Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
	published = folder
	return retained
end

-- Cette méthode permet d'oublier la manche (pistes, tirs, kills, record, clip, apparences, figurants publiés, demandes
-- en attente) lorsque le serveur repasse à idle.
function HighlightService.reset()
	token += 1
	table.clear(tracks)
	table.clear(shots)
	table.clear(kills)
	table.clear(metas)
	table.clear(streaks)
	table.clear(flicks)
	table.clear(pending)
	bestScore = nil
	clip = nil
	clipActors = {}
	if appearances then
		appearances:ClearAllChildren()
	end
	if published then
		published:Destroy()
		published = nil
	end
end

-- Cette méthode permet de brancher le clip de la partie lorsque le serveur démarre (sauf entraînement : `enabled` faux,
-- aucune piste ni notation).
function HighlightService.init(dependencies: Deps)
	deps = dependencies
	dependencies.povRemote.OnServerEvent:Connect(function(player, id, text)
		if not CheatLog.admit(player, dependencies.povRemote.Name, id, text) then
			return
		end
		onPovReceived(player, id, text)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local current = pending[player]
		if current then
			pending[player] = nil
			current.done(nil)
		end
	end)
end

return HighlightService
