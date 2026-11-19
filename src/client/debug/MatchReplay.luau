-- Rejeu d'un enregistrement de partie (#582), Studio seulement : la partie enregistrée dans le jeu publié
-- (debug/MatchRecorder) est reconstruite dans la vraie map pour être filmée (docs/promo.md, « Enregistreur de
-- partie »). Chaque participant devient un figurant (rig du jeu, tenue, arme 3P et skin, animation de déplacement,
-- actions de l'arme), les tirs ont leur effet de tir équipé, leur son et leur douille, les morts leur ragdoll, les kills
-- leur ligne au kill feed ; les pas s'entendent. En vue du joueur (#586), le HUD de jeu est celui de la partie (viseur,
-- hitmarker et son de touche, munitions, vitesse, barre d'armes, timer, rang, série de kills) et l'annonceur parle.
-- Pas de musique pendant le rejeu (elle se choisit au montage).
-- Piloté par attributs du joueur, posés en contexte Server (répliqués) :
-- - `MatchReplay` = nom de l'enregistrement (recordings/<Nom>/), publié par server/MatchReplayService ; nil arrête ;
-- - `MatchReplayRun` (nombre, à changer) relance avec les réglages courants, sans recharger ;
-- - `MatchReplaySpeed` (défaut 1 ; 0.25 pour filmer au ralenti), `MatchReplayFrom` / `MatchReplayTo` (s) ;
-- - `MatchReplayCamera` : "pov" (défaut : yeux du joueur qui enregistrait, viewmodel, lunette), "follow" (derrière),
--   "side" (de côté, perpendiculaire à la course), "front" (devant), "orbit" (tour lent), "track" (posée en
--   `MatchReplayCameraPosition`, suit la cible), "fixed" (`MatchReplayCameraCFrame`) ;
-- - `MatchReplayTarget` (id, défaut : le joueur qui enregistrait), `MatchReplayDistance`, `MatchReplayHeight`,
--   `MatchReplayFov` (plans hors POV), `MatchReplayHud` (false : sans interface de jeu) ;
-- - `MatchReplayAudio` (true : passe du son, à vitesse 1) : bip BEEP_LEAD s avant la lecture, sur lequel l'outil de
--   capture cale le son ; la lecture part exactement BEEP_LEAD s après le bip.
-- Au ralenti, positions, caméra, pistes d'animation, actions 3P, kill feed, chute des corps (gravité × vitesse²),
-- effets de tir, douilles et interpolations du HUD (EffectClock) suivent le temps du rejeu ; seuls les sons restent en
-- temps réel (le son se prend dans une seconde passe à vitesse 1). Écran noir SLATE s avant et TAIL s après la
-- lecture : l'outil de capture (tools/matchrec/capture.py) y cale le début, la fin et le cadre du viewport.
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraConfig = require(Shared:WaitForChild("CameraConfig"))
local CharacterAnimator = require(Shared:WaitForChild("CharacterAnimator"))
local CharacterAppearance = require(Shared:WaitForChild("CharacterAppearance"))
local MatchRecordRules = require(Shared:WaitForChild("MatchRecordRules"))
local ParticipantRules = require(Shared:WaitForChild("ParticipantRules"))
local ShotSoundRules = require(Shared:WaitForChild("ShotSoundRules"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local WeaponThirdPerson = require(Shared:WaitForChild("WeaponThirdPerson"))
local FootstepSounds = require(script.Parent.Parent.systems.audio.FootstepSounds)
local HitSound = require(script.Parent.Parent.systems.audio.HitSound)
local DeathRagdoll = require(script.Parent.Parent.systems.game.DeathRagdoll)
local EffectClock = require(script.Parent.Parent.systems.game.EffectClock)
local KillAnnouncer = require(script.Parent.Parent.systems.game.KillAnnouncer)
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local SoundChannels = require(script.Parent.Parent.systems.settings.SoundChannels)
local AnimationSoundSystem = require(script.Parent.Parent.systems.weapon.AnimationSoundSystem)
local CasingEjection = require(script.Parent.Parent.systems.weapon.CasingEjection)
local ShotEffects = require(script.Parent.Parent.systems.weapon.ShotEffects)
local ViewmodelClone = require(script.Parent.Parent.systems.weapon.ViewmodelClone)
local AmmoCounter = require(script.Parent.Parent.ui.AmmoCounter)
local HUDRules = require(script.Parent.Parent.ui.HUDRules)
local HUDState = require(script.Parent.Parent.ui.HUDState)
local Hitmarker = require(script.Parent.Parent.ui.Hitmarker)
local KillFeed = require(script.Parent.Parent.ui.KillFeed)
local MenuCursor = require(script.Parent.Parent.ui.MenuCursor)
local RoundHUD = require(script.Parent.Parent.ui.RoundHUD)
local ScopeOverlay = require(script.Parent.Parent.ui.ScopeOverlay)
local Speedometer = require(script.Parent.Parent.ui.Speedometer)
local UIKit = require(script.Parent.Parent.ui.UIKit)
local WeaponBar = require(script.Parent.Parent.ui.WeaponBar)

local E = MatchRecordRules.Event

local A = {
	name = "MatchReplay",
	ready = "MatchReplayReady",
	run = "MatchReplayRun",
	speed = "MatchReplaySpeed",
	from = "MatchReplayFrom",
	to = "MatchReplayTo",
	camera = "MatchReplayCamera",
	target = "MatchReplayTarget",
	distance = "MatchReplayDistance",
	height = "MatchReplayHeight",
	fov = "MatchReplayFov",
	cframe = "MatchReplayCameraCFrame",
	position = "MatchReplayCameraPosition",
	hud = "MatchReplayHud",
	audio = "MatchReplayAudio",
}

local DATA_NAME = "MatchReplayData"
local BIND_NAME = "MatchReplay"
-- Écran noir (s, temps réel) avant et après la lecture : repères de l'outil de capture
local SLATE = 1.5
local TAIL = 1
-- Une victime reste couchée au moins ce temps (s du rejeu) avant que sa piste puisse la remontrer
local DOWN_TIME = 1.5
-- Vitesse verticale (studs/s) au-delà de laquelle un figurant est en l'air, pour son animation
local AIR_SPEED = 2
-- Durée (s du rejeu) pendant laquelle une action 3P est encore tenue à l'heure du rejeu
local ACTION_HOLD = 2
-- Réglages par défaut des plans hors POV
local DEFAULT_DISTANCE = 10
local DEFAULT_HEIGHT = 3
local DEFAULT_FOV = 70
-- Lissage (1/s du rejeu) du cap des plans suivis
local HEADING_RATE = 5
-- Kill feed : redessiné au plus tard toutes les FEED_REFRESH s réelles (ses lignes expirent en temps réel)
local FEED_REFRESH = 2
local FEED_MARGIN_RIGHT = 20
local FEED_MARGIN_TOP = 12
-- Passe du son (#586) : bip de synchro joué BEEP_LEAD s (réelles) avant la lecture, pendant l'écran noir ; même valeur
-- dans tools/matchrec/capture.py
local BEEP_LEAD = 0.5
local BEEP_SOUND = "rbxasset://sounds/volume_slider.ogg"
-- Écart (s du rejeu) sur lequel la vitesse du compteur est mesurée
local SPEED_WINDOW = 0.1
-- Interface du jeu laissée affichée pendant un rejeu en vue du joueur avec HUD (ScreenGui par nom) ; le reste est caché
local HUD_GUIS = table.freeze({
	AmmoCounter = true,
	Crosshair = true,
	Hitmarker = true,
	RoundHUD = true,
	RoundTimerOverMenu = true,
	ScopeOverlay = true,
	Speedometer = true,
	WeaponBar = true,
})

type Event = MatchRecordRules.Event
type Held = ViewmodelClone.Held

type Actor = {
	id: number,
	info: MatchRecordRules.Actor,
	model: Model,
	root: BasePart,
	parts: { BasePart },
	decals: { Decal },
	animator: any?,
	visible: boolean,
	hint: number,
	lastPos: Vector3?,
	velocity: Vector3,
	downAt: number?,
	action: string?,
	actionAt: number?,
	weapon: string?, -- clé outil|skin de l'arme 3P posée
	style: string?, -- effet de tir équipé (#586)
	feet: number, -- hauteur de la racine au-dessus des pieds (pas entendus aux pieds)
}

type Session = {
	match: MatchRecordRules.Match,
	me: number?,
	speed: number,
	from: number,
	to: number,
	mode: string,
	targetId: number?,
	t: number,
	phase: string, -- "slate", "play", "tail"
	phaseAt: number, -- os.clock du début de la phase
	nextEvent: number,
	actors: { [number]: Actor },
	folder: Folder,
	gui: ScreenGui,
	cover: Frame,
	feed: KillFeed.Feed?,
	feedLines: { { line: KillFeed.FeedLine, t: number } },
	feedDrawnAt: number,
	held: { [string]: Held },
	viewmodel: Held?,
	outfit: string?, -- tenue du joueur qui enregistrait (bras du viewmodel)
	swing: number,
	povHint: number,
	povVisible: boolean,
	scoped: boolean,
	heading: Vector3?,
	conns: { RBXScriptConnection },
	sounds: { Instance },
	disabledGuis: { ScreenGui },
	playerGui: PlayerGui,
	gravity: number,
	menuWasRunning: boolean, -- scène 3D du menu arrêtée pendant le rejeu (elle tient la caméra), relancée ensuite
	cursorWasShown: boolean, -- souris imposée par le menu (MenuCursor) retirée pendant le rejeu, rendue ensuite
	frames: number,
	finished: boolean,
	-- Rejeu fidèle (#586)
	gameHud: boolean, -- HUD de jeu piloté (vue du joueur, MatchReplayHud non coupé)
	audio: boolean, -- passe du son : bip de synchro, lecture calée dessus
	beepAt: number?, -- os.clock du bip
	myStyle: string?, -- effet de tir du joueur qui enregistrait
	myTools: { string }, -- armes du joueur qui enregistrait (barre d'armes)
	round: Event?, -- dernier état de la manche (timer)
	shownLeft: number?,
	alive: boolean?, -- joueur rejoué en vie (HUD de jeu affiché)
	speedA: { number },
	speedB: { number },
}

local MatchReplay = {}
local hideOtherGuis: (Session) -> ()

local player: Player
local cache: { name: string, match: MatchRecordRules.Match }? = nil
local current: Session? = nil
local povOut = table.create(8, 0)
local actorOut = table.create(4, 0)
local POV_STEP_COLS = { [8] = true }

-- Cette méthode permet d'écrire une ligne préfixée dans la sortie lorsque le rejeu avance.
local function log(text: string)
	print("[MatchReplay] " .. text)
end

-- Cette méthode permet de lire un attribut numérique du joueur lorsqu'un rejeu démarre (défaut s'il est absent).
local function numberAttr(name: string, default: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" and value == value then value else default
end

-- Cette méthode permet de nommer l'arme d'un figurant ou du viewmodel (outil et skin) lorsqu'elle est posée.
local function weaponKey(tool: string?, skin: string?): string
	return (tool or "") .. "|" .. (skin or "")
end

-- ── Chargement ─────────────────────────────────────────────────────────────

-- Cette méthode permet de fusionner les morceaux publiés par le serveur en une partie lorsque l'enregistrement est
-- prêt ; gardée en cache pour les relances. nil si aucun morceau n'est lisible.
local function load(name: string): MatchRecordRules.Match?
	if cache and cache.name == name then
		return cache.match
	end
	local data = ReplicatedStorage:WaitForChild(DATA_NAME, 10)
	local chunks = data and data:WaitForChild("Chunks", 10)
	if not chunks then
		log("données introuvables dans ReplicatedStorage." .. DATA_NAME)
		return nil
	end
	local values = chunks:GetChildren()
	table.sort(values, function(a, b)
		return a.Name < b.Name
	end)
	local match = MatchRecordRules.newMatch()
	local read = 0
	for _, value in values do
		if not value:IsA("StringValue") then
			continue
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, value.Value)
		local chunk, why = MatchRecordRules.readChunk(if ok then decoded else nil)
		if not chunk then
			log(string.format("morceau %s écarté : %s", value.Name, tostring(why or decoded)))
			continue
		end
		local added, reason = MatchRecordRules.addChunk(match, chunk)
		if added then
			read += 1
		else
			log(string.format("morceau %s écarté : %s", value.Name, tostring(reason)))
		end
	end
	if read == 0 then
		return nil
	end
	MatchRecordRules.finish(match)
	cache = { name = name, match = match }
	return match
end

-- ── Figurants ──────────────────────────────────────────────────────────────

-- Cette méthode permet de montrer ou cacher un figurant lorsqu'il entre dans sa piste ou en sort.
local function setVisible(actor: Actor, visible: boolean)
	if actor.visible == visible then
		return
	end
	actor.visible = visible
	local modifier = if visible then 0 else 1
	for _, part in actor.parts do
		part.LocalTransparencyModifier = modifier
	end
	for _, decal in actor.decals do
		decal.Transparency = modifier
	end
end

-- Cette méthode permet de relever les pièces et décalques d'un figurant lorsqu'il est créé ou que son arme ou sa tenue
-- change (pièces ajoutées).
local function collectParts(actor: Actor)
	table.clear(actor.parts)
	table.clear(actor.decals)
	for _, inst in actor.model:GetDescendants() do
		if inst:IsA("BasePart") then
			table.insert(actor.parts, inst)
			inst.LocalTransparencyModifier = if actor.visible then 0 else 1
		elseif inst:IsA("Decal") then
			table.insert(actor.decals, inst)
			inst.Transparency = if actor.visible then 0 else 1
		end
	end
end

-- Cette méthode permet de créer le figurant d'un participant lorsque le rejeu se prépare : rig du jeu (publié par le
-- serveur), habillé, racine ancrée, sans collision ; caché jusqu'à sa première position.
local function buildActor(session: Session, rig: Model, info: MatchRecordRules.Actor): Actor?
	local model = rig:Clone()
	model.Name = "MatchActor" .. tostring(info.id)
	for _, inst in model:GetDescendants() do
		if inst:IsA("LuaSourceContainer") or inst:IsA("ForceField") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.Anchored = inst.Name == "HumanoidRootPart"
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end
	CharacterAppearance.apply(model, nil)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
	end
	model.Parent = session.folder
	local actor: Actor = {
		id = info.id,
		info = info,
		model = model,
		root = root,
		parts = {},
		decals = {},
		animator = if humanoid then CharacterAnimator.new(humanoid) else nil,
		visible = true,
		hint = 0,
		velocity = Vector3.zero,
		feet = root.Size.Y / 2 + (if humanoid then humanoid.HipHeight else 2),
	}
	if actor.animator then
		actor.animator:setTimeScale(session.speed)
	end
	collectParts(actor)
	setVisible(actor, false)
	return actor
end

-- Cette méthode permet de poser l'arme 3P d'un figurant (outil, skin) lorsqu'il en change ; mains vides sans outil.
local function setActorWeapon(actor: Actor, tool: string?, skin: string?)
	local key = weaponKey(tool, skin)
	if actor.weapon == key then
		return
	end
	actor.weapon = key
	local source = ViewmodelClone.tool(tool)
	if not source then
		WeaponThirdPerson.detach(actor.model)
	else
		local weaponName = source:GetAttribute("WeaponName")
		local viewmodelName = source:GetAttribute("ViewmodelName")
		WeaponThirdPerson.attach(
			actor.model,
			if type(weaponName) == "string" then weaponName else source.Name,
			if type(viewmodelName) == "string" then viewmodelName else nil,
			skin
		)
	end
	collectParts(actor)
end

-- ── Viewmodel du joueur qui enregistrait ──────────────────────────────────

-- Cette méthode permet de jouer une piste du viewmodel en main à la vitesse du rejeu lorsqu'une action y arrive (tir,
-- recharge, inspection, sortie), avec ses sons à marqueurs ; rien sans viewmodel ou sans piste de ce nom.
local function playHeld(session: Session, name: string, lethal: boolean?)
	local held = session.viewmodel
	if not held then
		return
	end
	local cfg = WeaponConfig.Weapons[held.weapon]
	local trackName = name
	if name == "Shoot" and cfg and cfg.IsMelee and cfg.ShootAnimations and #cfg.ShootAnimations > 0 then
		session.swing = session.swing % #cfg.ShootAnimations + 1
		trackName = cfg.ShootAnimations[session.swing]
	end
	local track = held.tracks[trackName]
	if not track then
		return
	end
	track.Looped = false
	track:Stop(0)
	track:Play(if name == "Shoot" and cfg then cfg.AttackFadeTime else nil)
	track:AdjustSpeed(session.speed)
	local sounds = cfg and cfg.AnimationSounds and cfg.AnimationSounds[trackName] or {}
	for _, conn in AnimationSoundSystem.connectSoundMarkers(track, held.model, sounds) do
		table.insert(session.conns, conn)
	end
	if name == "Shoot" then
		-- Douille à l'ouverture de culasse, comme en partie ; branchement rendu à l'arrêt de la piste (tir suivant)
		local casing = CasingEjection.connectMarker(track, held.model)
		if casing then
			table.insert(session.conns, casing)
			table.insert(
				session.conns,
				track.Stopped:Once(function()
					casing:Disconnect()
				end)
			)
		end
	end
	if name == "Shoot" and cfg and cfg.IsMelee then
		local conn = AnimationSoundSystem.connectSoundMarker(
			track,
			held.model,
			"Stab Sound",
			if lethal then "Shoot_human" else "Shoot_void"
		)
		if conn then
			table.insert(session.conns, conn)
		end
	end
end

-- Cette méthode permet de mettre une arme en main du viewmodel lorsque le rejeu y arrive : l'arme précédente est
-- rangée, la nouvelle préparée au besoin (bras habillés de la tenue) et montrée avec sa boucle Idle ; `animate` joue
-- sa sortie.
local function equipHeld(session: Session, tool: string?, skin: string?, animate: boolean)
	local key = weaponKey(tool, skin)
	local held = session.held[key]
	if not held and tool then
		local camera = workspace.CurrentCamera
		local built = camera and ViewmodelClone.build(camera, tool, skin)
		if built then
			CharacterAppearance.dressArms(built.model, session.outfit)
			session.held[key] = built
			held = built
		end
	end
	if held == session.viewmodel then
		return
	end
	local previous = session.viewmodel
	if previous then
		for _, track in previous.tracks do
			track:Stop(0)
		end
		ViewmodelClone.setVisible(previous, false)
	end
	session.viewmodel = held
	session.swing = 0
	if not held then
		return
	end
	ViewmodelClone.setVisible(held, session.mode == "pov" and session.povVisible and not session.scoped)
	local idle = held.tracks.Idle
	if idle then
		idle:Play(0)
		idle:AdjustSpeed(session.speed)
	end
	if animate then
		playHeld(session, "Equip")
	end
end

-- ── Évènements ─────────────────────────────────────────────────────────────

-- Cette méthode permet de faire entendre en 3D le tir d'un figurant lorsque le rejeu y arrive (son de son arme 3P).
local function playActorShot(session: Session, actor: Actor)
	local gun = actor.model:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
	local handle = gun and gun:FindFirstChild("Handle")
	local template = handle and handle:FindFirstChild(ShotSoundRules.DEFAULT.Sound)
	if not (template and template:IsA("Sound")) then
		return
	end
	local sound = template:Clone()
	SoundChannels.weapon(sound)
	sound.Looped = false
	sound.Parent = handle
	sound:Play()
	table.insert(session.sounds, sound)
end

-- Cette méthode permet de redessiner le kill feed avec les lignes encore valides à l'instant du rejeu lorsqu'une ligne
-- arrive ou expire (le feed compte en temps réel : il est repeint pour suivre le temps du rejeu).
local function drawFeed(session: Session, force: boolean)
	local feed = session.feed
	if not feed then
		return
	end
	local kept = {}
	for _, entry in session.feedLines do
		if session.t - entry.t < HUDRules.KILL_FEED_DURATION then
			table.insert(kept, entry)
		end
	end
	local changed = #kept ~= #session.feedLines
	session.feedLines = kept
	if not force and not changed and os.clock() - session.feedDrawnAt < FEED_REFRESH then
		return
	end
	session.feedDrawnAt = os.clock()
	KillFeed.clear(feed)
	for _, entry in kept do
		KillFeed.push(feed, entry.line)
	end
end

-- Cette méthode permet de lister les armes du joueur qui enregistrait (barre d'armes du HUD) lorsque le rejeu se prépare :
-- toutes celles qu'il sort pendant l'enregistrement.
local function toolsOf(match: MatchRecordRules.Match, me: number?): { string }
	local seen: { [string]: boolean } = {}
	local tools = {}
	for _, event in MatchRecordRules.eventsOf(match, E.EQUIP, me) do
		if event.tool and not seen[event.tool] then
			seen[event.tool] = true
			table.insert(tools, event.tool)
		end
	end
	return tools
end

-- Cette méthode permet de montrer ou cacher le HUD de jeu du rejeu lorsque le joueur rejoué apparaît ou meurt
-- (comme en partie : rien de ce HUD pendant la mort).
local function setGameHudAlive(session: Session, alive: boolean)
	if not session.gameHud or session.alive == alive then
		return
	end
	session.alive = alive
	HUDState.setReplay(alive)
	Speedometer.setVisible(alive)
	WeaponBar.setVisible(alive)
	AmmoCounter.setVisible(alive)
end

-- Cette méthode permet de mettre à jour le compteur de vitesse et le timer du HUD de jeu lorsqu'une image du rejeu est
-- rendue.
local function updateGameHud(session: Session)
	if not session.gameHud then
		return
	end
	if session.alive then
		Speedometer.update(
			MatchRecordRules.speedAt(session.match.pov, session.t, SPEED_WINDOW, session.speedA, session.speedB)
		)
	end
	local left = MatchRecordRules.timeLeftAt(session.round, session.t)
	if left and left ~= session.shownLeft then
		session.shownLeft = left
		RoundHUD.updateTimer(left)
	end
end

-- Cette méthode permet de faire entendre le pas d'un participant lorsque le rejeu y arrive : les siens sans position en
-- vue du joueur, ceux des autres en 3D à leurs pieds (figurant visible).
local function playStep(session: Session, event: Event)
	local kind = if event.ld then "land" else "step"
	if event.id == session.me and session.mode == "pov" then
		FootstepSounds.playOwn(kind)
		return
	end
	local actor = session.actors[event.id]
	if actor and actor.visible then
		FootstepSounds.playAt(actor.root.Position - Vector3.new(0, actor.feet, 0), kind)
	end
end

-- Cette méthode permet de rejouer un évènement lorsque le rejeu y arrive ; `live` faux au démarrage en cours de partie
-- (seuls l'arme, la tenue, l'effet de tir, l'action en cours et l'état du HUD sont posés, sans son ni effet).
local function handleEvent(session: Session, event: Event, live: boolean)
	local actor = session.actors[event.id]
	local mine = event.id == session.me
	local pov = session.mode == "pov"
	if event.k == E.EQUIP then
		if actor then
			setActorWeapon(actor, event.tool, event.skin)
		end
		if mine then
			equipHeld(session, event.tool, event.skin, live)
			if session.gameHud then
				WeaponBar.setReplay({ tools = session.myTools, equipped = event.tool })
			end
		end
	elseif event.k == E.FX then
		if actor then
			actor.style = event.s
		end
		if mine then
			session.myStyle = event.s
		end
	elseif event.k == E.AMMO then
		if mine and session.gameHud then
			AmmoCounter.setReplay({
				ammo = MatchRecordRules.decodeAmmo(event.m),
				reserve = MatchRecordRules.decodeAmmo(event.r),
			})
		end
	elseif event.k == E.ROUND then
		session.round = event
		if live and event.s ~= MatchRecordRules.ROUND_ACTIVE then
			KillAnnouncer.reset()
		end
	elseif event.k == E.SCORES then
		if session.gameHud then
			local rename = if session.me then { [session.me] = player.Name } else nil
			RoundHUD.updateScores(MatchRecordRules.decodeScores(event.sc, rename) :: any)
		end
	elseif event.k == E.OUTFIT then
		if actor then
			CharacterAppearance.dress(actor.model, event.o)
			collectParts(actor)
		end
		if mine then
			session.outfit = event.o
			for _, held in session.held do
				CharacterAppearance.dressArms(held.model, event.o)
			end
		end
	elseif event.k == E.ACTION then
		if actor and type(event.a) == "string" then
			actor.action = event.a
			actor.actionAt = event.t
			actor.model:SetAttribute(WeaponThirdPerson.ACTION_ATTR, event.a)
		end
		if live and mine and event.a == "Reload" then
			playHeld(session, "Reload")
		end
	elseif not live then
		return
	elseif event.k == E.HIT then
		if mine then
			HitSound.play()
			if session.gameHud and session.alive then
				Hitmarker.show(event.kl == true, event.hs == true)
			end
		end
	elseif event.k == E.STEP then
		playStep(session, event)
	elseif event.k == E.SHOT then
		local dir = MatchRecordRules.directionOf(event)
		local camera = workspace.CurrentCamera
		if mine and pov and camera then
			local lethal = false
			for i = session.nextEvent, math.min(session.nextEvent + 8, #session.match.events) do
				local other = session.match.events[i]
				if other.k == E.KILL and other.id == event.id and other.t - event.t < 0.5 then
					lethal = true
				end
			end
			playHeld(session, "Shoot", lethal)
			if dir then
				local model = if session.viewmodel then session.viewmodel.model else nil
				ShotEffects.playReplay(
					model,
					camera.CFrame.Position,
					dir,
					{ session.folder, camera },
					nil,
					session.myStyle,
					session.scoped
				)
			end
		elseif actor and actor.visible then
			playActorShot(session, actor)
			local gun = actor.model:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
			if dir and camera then
				local eye = actor.root.Position + Vector3.new(0, CameraConfig.CAM_HEIGHT_STAND - 0.4, 0)
				ShotEffects.playReplay(gun, eye, dir, { session.folder, camera }, camera.CFrame.Position, actor.style)
			end
			-- Douille de l'arme 3P à l'ouverture de culasse (délai de l'arme, au temps du rejeu)
			local weaponName = gun and gun:GetAttribute("WeaponName")
			local cfg = type(weaponName) == "string" and WeaponConfig.Weapons[weaponName]
			if cfg and type(cfg.CasingEjectDelay) == "number" then
				EffectClock.delay(cfg.CasingEjectDelay, CasingEjection.ejectReplay, gun)
			end
		end
	elseif event.k == E.INSPECT then
		if mine then
			playHeld(session, "Inspect")
		end
	elseif event.k == E.DEATH then
		if actor and actor.visible then
			local kill = MatchRecordRules.killOf(session.match, event.id, event.t)
			DeathRagdoll.spawn(
				actor.model,
				if kill then MatchRecordRules.directionOf(kill) else nil,
				kill and kill.w,
				kill ~= nil and kill.hs == true,
				actor.velocity * session.speed
			)
			-- Ragdoll au ralenti : élan ramené à la vitesse du rejeu (la gravité l'est déjà)
			local corpses = workspace:FindFirstChild("Ragdolls")
			local corpse = corpses and corpses:FindFirstChild(actor.model.Name .. "_Ragdoll")
			if corpse and session.speed ~= 1 then
				for _, part in corpse:GetDescendants() do
					if part:IsA("BasePart") then
						part.AssemblyLinearVelocity *= session.speed
					end
				end
			end
			setVisible(actor, false)
			actor.downAt = event.t
		end
		if mine then
			KillAnnouncer.reset()
			if session.viewmodel then
				ViewmodelClone.setVisible(session.viewmodel, false)
			end
		end
	elseif event.k == E.KILL then
		if mine and event.victim ~= session.me then
			-- Annonceur et série de kills (crâne du HUD), comme pour le joueur qui tue
			KillAnnouncer.onKill(event.hs == true)
		end
		local killer = session.match.actors[event.id]
		local victim = event.victim and session.match.actors[event.victim]
		table.insert(session.feedLines, {
			t = event.t,
			line = {
				killer = if killer then killer.name else "?",
				killerIsBot = ParticipantRules.isBotId(event.id),
				victim = if victim then victim.name else "?",
				victimIsBot = event.victim ~= nil and ParticipantRules.isBotId(event.victim),
				weapon = event.w,
				headshot = event.hs == true,
				mine = mine,
			},
		})
		drawFeed(session, true)
	end
end

-- ── Image ──────────────────────────────────────────────────────────────────

-- Cette méthode permet de placer chaque figurant à l'instant du rejeu lorsqu'une image est rendue : position et cap
-- interpolés (caméra du joueur qui enregistrait pour lui-même, plus fine), animation d'après sa vitesse, action 3P
-- tenue à l'heure du rejeu ; caché hors de sa piste, pendant sa mort, et en POV pour le joueur lui-même.
local function placeActors(session: Session, dtReplay: number)
	local t = session.t
	local now = workspace:GetServerTimeNow()
	for id, actor in session.actors do
		local present, pos, yaw
		if id == session.me and #session.match.pov.t > 0 then
			local ok, hint = MatchRecordRules.sample(session.match.pov, t, povOut, session.povHint, nil, POV_STEP_COLS)
			session.povHint = hint
			if ok then
				present, pos, yaw = true, Vector3.new(povOut[1], povOut[2], povOut[3]), -math.rad(povOut[5])
			end
		end
		if not present then
			local ok, hint = MatchRecordRules.sample(actor.info.track, t, actorOut, actor.hint, 4)
			actor.hint = hint
			if ok then
				present, pos, yaw = true, Vector3.new(actorOut[1], actorOut[2], actorOut[3]), actorOut[4]
			end
		end
		local down = actor.downAt ~= nil and t >= actor.downAt and t < actor.downAt + DOWN_TIME
		local hidden = id == session.me and session.mode == "pov"
		if not present or down or hidden then
			setVisible(actor, false)
			actor.lastPos = nil
			continue
		end
		actor.root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		if not actor.visible and actor.downAt and t >= actor.downAt then
			actor.downAt = nil
		end
		setVisible(actor, true)
		local velocity = if actor.lastPos and dtReplay > 0 then (pos - actor.lastPos) / dtReplay else Vector3.zero
		actor.lastPos = pos
		actor.velocity = velocity
		if actor.animator then
			actor.animator:update({
				onGround = math.abs(velocity.Y) <= AIR_SPEED,
				crouching = false,
				surfing = false,
				speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude,
				verticalSpeed = velocity.Y,
			})
		end
		if actor.actionAt and t - actor.actionAt < ACTION_HOLD then
			actor.model:SetAttribute(WeaponThirdPerson.ACTION_AT_ATTR, now - (t - actor.actionAt))
		end
	end
end

-- Cette méthode permet de lire la position, le cap et la vitesse de la cible des plans suivis lorsqu'une image est
-- rendue ; nil si elle n'est pas visible.
local function targetState(session: Session): (Vector3?, Vector3?, Vector3?)
	local actor = session.targetId and session.actors[session.targetId]
	if not actor or not actor.visible then
		return nil, nil, nil
	end
	return actor.root.Position, actor.root.CFrame.LookVector, actor.velocity
end

-- Cette méthode permet de poser la caméra du plan choisi lorsqu'une image est rendue : yeux du joueur (POV, viewmodel,
-- lunette), plan suivi (derrière, côté, devant, tour), posé ou fixe.
local function placeCamera(session: Session, dtReplay: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local mode = session.mode
	if mode == "pov" then
		local present, hint =
			MatchRecordRules.sample(session.match.pov, session.t, povOut, session.povHint, nil, POV_STEP_COLS)
		session.povHint = hint
		session.povVisible = present
		if present then
			camera.CFrame = CFrame.new(povOut[1], povOut[2] + povOut[4], povOut[3])
				* CFrame.Angles(0, math.rad(-povOut[5]), 0)
				* CFrame.Angles(math.rad(povOut[6]), 0, 0)
			camera.FieldOfView = povOut[7]
			local scoped = bit32.band(math.floor(povOut[8]), MatchRecordRules.FLAG_SCOPED) ~= 0
			if scoped ~= session.scoped then
				session.scoped = scoped
				ScopeOverlay.setVisible(scoped)
			end
		end
		local held = session.viewmodel
		if held then
			ViewmodelClone.setVisible(held, present and not session.scoped)
			held.model:PivotTo(camera.CFrame * held.offset)
		end
		return
	end
	camera.FieldOfView = numberAttr(A.fov, DEFAULT_FOV)
	if mode == "fixed" then
		local cf = player:GetAttribute(A.cframe)
		if typeof(cf) == "CFrame" then
			camera.CFrame = cf
		end
		return
	end
	local pos, look, velocity = targetState(session)
	if not pos then
		return
	end
	local distance = numberAttr(A.distance, DEFAULT_DISTANCE)
	local height = numberAttr(A.height, DEFAULT_HEIGHT)
	local focus = pos + Vector3.new(0, 1.5, 0)
	if mode == "track" then
		local at = player:GetAttribute(A.position)
		if typeof(at) == "Vector3" then
			camera.CFrame = CFrame.lookAt(at, focus)
		end
		return
	end
	if mode == "orbit" then
		local angle = session.t * 0.3
		local offset = Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)
		camera.CFrame = CFrame.lookAt(focus + offset, focus)
		return
	end
	-- Cap lissé : direction de la course pour le plan de côté, sinon regard du personnage
	local flat = Vector3.new(look.X, 0, look.Z)
	if mode == "side" and velocity and Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 2 then
		flat = Vector3.new(velocity.X, 0, velocity.Z)
	end
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	local heading = session.heading
	if heading then
		local alpha = 1 - math.exp(-HEADING_RATE * dtReplay)
		local blended = heading:Lerp(flat, alpha)
		heading = if blended.Magnitude > 1e-3 then blended.Unit else flat
	else
		heading = flat
	end
	session.heading = heading
	local h = heading :: Vector3
	local offset
	if mode == "side" then
		offset = h:Cross(Vector3.yAxis) * distance + Vector3.new(0, height * 0.5, 0)
		camera.CFrame = CFrame.lookAt(focus + offset, focus + h * 2)
		return
	elseif mode == "front" then
		offset = h * distance + Vector3.new(0, height, 0)
	else
		offset = -h * distance + Vector3.new(0, height, 0)
	end
	camera.CFrame = CFrame.lookAt(focus + offset, focus)
end

-- ── Cycle de vie ───────────────────────────────────────────────────────────

-- Cette méthode permet de tout détruire et de rendre l'écran, la gravité et l'interface du jeu lorsque le rejeu se
-- termine ou est interrompu.
local function cleanup(session: Session)
	if session.finished then
		return
	end
	session.finished = true
	if current == session then
		current = nil
	end
	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, conn in session.conns do
		conn:Disconnect()
	end
	for _, actor in session.actors do
		if actor.animator then
			actor.animator:destroy()
		end
	end
	for _, sound in session.sounds do
		sound:Destroy()
	end
	for _, held in session.held do
		for _, track in held.tracks do
			track:Stop(0)
		end
		held.model:Destroy()
	end
	session.folder:Destroy()
	if session.feed then
		KillFeed.destroy(session.feed)
	end
	session.gui:Destroy()
	DeathRagdoll.clear()
	if session.scoped then
		ScopeOverlay.setVisible(false)
	end
	workspace.Gravity = session.gravity
	EffectClock.setScale(1)
	SoundChannels.setMusicMuted(false)
	KillAnnouncer.reset()
	if session.gameHud then
		-- HUD de jeu rendu à l'état du client (le rejeu se lance depuis le menu : masqué)
		local show = HUDRules.gameHudVisible(HUDState.get().gameState)
		HUDState.setReplay(false)
		AmmoCounter.setReplay(nil)
		WeaponBar.setReplay(nil)
		Speedometer.update(0)
		Speedometer.setVisible(show)
		WeaponBar.setVisible(show)
		AmmoCounter.setVisible(show)
		RoundHUD.updateScores({})
		if not show then
			RoundHUD.hide()
		end
	end
	for _, gui in session.disabledGuis do
		gui.Enabled = true
	end
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, true)
	UserInputService.MouseIconEnabled = true
	if session.cursorWasShown then
		MenuCursor.show()
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = CameraConfig.DEFAULT_FOV
	end
	if session.menuWasRunning then
		MenuScene.start()
	end
end

-- Cette méthode permet de cacher l'interface du jeu hors HUD de jeu lorsque le rejeu démarre puis à chaque image : un
-- écran abonné à HUDState (chat, affichage des touches) se réaffiche quand le rejeu change cet état. Rendue au nettoyage.
function hideOtherGuis(session: Session)
	for _, child in session.playerGui:GetChildren() do
		local kept = child == session.gui
			or child.Name == "ScopeOverlay"
			or (session.gameHud and HUD_GUIS[child.Name] == true)
		if child:IsA("ScreenGui") and child.Enabled and not kept then
			child.Enabled = false
			if not table.find(session.disabledGuis, child) then
				table.insert(session.disabledGuis, child)
			end
		end
	end
end

-- Cette méthode permet de rendre une image du rejeu lorsqu'il tourne : écran noir de départ, lecture (temps du rejeu
-- = temps réel × vitesse), écran noir de fin, puis nettoyage.
local function render(session: Session, dt: number)
	local now = os.clock()
	if session.phase ~= "tail" then
		hideOtherGuis(session)
	end
	if session.phase == "slate" then
		if session.audio and not session.beepAt and now - session.phaseAt >= SLATE - BEEP_LEAD then
			-- Repère du son : la lecture part BEEP_LEAD s après ce bip (tools/matchrec/capture.py, passe du son)
			local beep = Instance.new("Sound")
			beep.Name = "MatchReplayBeep"
			beep.SoundId = BEEP_SOUND
			beep.Volume = 1
			beep.Parent = SoundService
			beep:Play()
			table.insert(session.sounds, beep)
			session.beepAt = now
		end
		if now - session.phaseAt >= SLATE then
			session.phase = "play"
			session.phaseAt = now
			session.cover.Visible = false
			if session.beepAt then
				-- Instant 0 de la lecture calé sur le bip ; cette image le dépasse déjà de quelques ms
				session.t = session.from
					+ math.max(0, now - session.beepAt - BEEP_LEAD) * session.speed
					- dt * session.speed
			end
			workspace.Gravity = session.gravity * session.speed * session.speed
			log(
				string.format(
					"PLAY %.2f → %.2f s, vitesse %.2f, plan %s",
					session.from,
					session.to,
					session.speed,
					session.mode
				)
			)
		else
			placeActors(session, 0)
			placeCamera(session, 0)
			return
		end
	elseif session.phase == "tail" then
		if now - session.phaseAt >= TAIL then
			log("END")
			cleanup(session)
		end
		return
	end
	local dtReplay = dt * session.speed
	session.t = math.min(session.t + dtReplay, session.to)
	session.frames += 1
	local events = session.match.events
	while session.nextEvent <= #events and events[session.nextEvent].t <= session.t do
		local event = events[session.nextEvent]
		session.nextEvent += 1
		handleEvent(session, event, true)
	end
	placeActors(session, dtReplay)
	placeCamera(session, dtReplay)
	setGameHudAlive(session, session.povVisible)
	updateGameHud(session)
	drawFeed(session, false)
	if session.t >= session.to then
		local real = now - session.phaseAt
		log(
			string.format(
				"FIN de lecture : %.2f s du rejeu en %.2f s réelles, %d images (%.1f i/s)",
				session.to - session.from,
				real,
				session.frames,
				session.frames / math.max(real, 1e-3)
			)
		)
		session.phase = "tail"
		session.phaseAt = now
		session.cover.Visible = true
		workspace.Gravity = session.gravity
		setGameHudAlive(session, false)
	end
end

-- Cette méthode permet de construire l'interface du rejeu lorsqu'il démarre : écran noir (repère de capture) et kill
-- feed à droite comme en partie.
local function buildGui(hud: boolean): (ScreenGui, Frame, KillFeed.Feed?)
	local gui = UIKit.create("ScreenGui", {
		Name = "MatchReplay",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 60,
	}) :: ScreenGui
	local feed = if hud
		then KillFeed.mount(UIKit.scaledRoot(gui, true), UDim2.new(1, -FEED_MARGIN_RIGHT, 0, FEED_MARGIN_TOP))
		else nil
	local cover = UIKit.frame({
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UITheme.Colors.Black,
		BackgroundTransparency = 0,
		ZIndex = 10,
		Parent = gui,
	}) :: Frame
	return gui, cover, feed
end

-- Cette méthode permet d'arrêter le rejeu en cours lorsque l'attribut est retiré ou qu'une relance arrive.
function MatchReplay.stop()
	local session = current
	if session then
		cleanup(session)
	end
end

-- Cette méthode permet de lancer le rejeu de l'enregistrement prêt avec les réglages courants (attributs) lorsqu'il est
-- publié par le serveur ou relancé.
local function start(name: string)
	MatchReplay.stop()
	local match = load(name)
	local data = ReplicatedStorage:FindFirstChild(DATA_NAME)
	local rig = data and data:FindFirstChild("Rig")
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not match or not (rig and rig:IsA("Model")) or not playerGui then
		log(
			"rejeu impossible : "
				.. (
					if not match
						then "aucun morceau lisible"
						elseif not playerGui then "PlayerGui absent"
						else "rig absent"
				)
		)
		return
	end
	local summary = MatchRecordRules.summary(match)
	log(
		string.format(
			"%s : %.1f s, %d participant(s), %d kill(s), %d tir(s), caméra %d relevés, %d morceau(x) manquant(s), map %s",
			name,
			summary.duration,
			summary.actors,
			summary.kills,
			summary.shots,
			summary.povRows,
			summary.missing,
			tostring(match.meta.map)
		)
	)
	local speed = math.clamp(numberAttr(A.speed, 1), 0.05, 4)
	local from = math.clamp(numberAttr(A.from, 0), 0, match.duration)
	local to = math.clamp(numberAttr(A.to, match.duration), from, match.duration)
	local mode = player:GetAttribute(A.camera)
	mode = if type(mode) == "string" and mode ~= "" then mode else "pov"
	local hud = player:GetAttribute(A.hud) ~= false
	local gameHud = hud and mode == "pov"
	local gui, cover, feed = buildGui(hud)
	local folder = Instance.new("Folder")
	folder.Name = "MatchReplay"
	folder.Parent = workspace
	local session: Session = {
		match = match,
		me = match.me,
		speed = speed,
		from = from,
		to = to,
		mode = mode,
		targetId = numberAttr(A.target, match.me or 0),
		t = from,
		phase = "slate",
		phaseAt = os.clock(),
		nextEvent = 1,
		actors = {},
		folder = folder,
		gui = gui,
		cover = cover,
		feed = feed,
		feedLines = {},
		feedDrawnAt = 0,
		held = {},
		viewmodel = nil,
		outfit = nil,
		swing = 0,
		povHint = 0,
		povVisible = false,
		scoped = false,
		heading = nil,
		conns = {},
		sounds = {},
		disabledGuis = {},
		playerGui = playerGui,
		gravity = workspace.Gravity,
		menuWasRunning = MenuScene.isRunning(),
		cursorWasShown = MenuCursor.isShown(),
		frames = 0,
		finished = false,
		gameHud = gameHud,
		audio = player:GetAttribute(A.audio) == true,
		beepAt = nil,
		myStyle = nil,
		myTools = toolsOf(match, match.me),
		round = nil,
		shownLeft = nil,
		alive = nil,
		speedA = table.create(4, 0),
		speedB = table.create(4, 0),
	}
	current = session
	if session.audio then
		task.spawn(function()
			local sample = Instance.new("Sound")
			sample.SoundId = BEEP_SOUND
			pcall(ContentProvider.PreloadAsync, ContentProvider, { sample })
		end)
	end
	-- Effets et HUD à la vitesse du rejeu, musique coupée (#586)
	EffectClock.setScale(speed)
	SoundChannels.setMusicMuted(true)
	if session.menuWasRunning then
		MenuScene.stop()
	end
	hideOtherGuis(session)
	gui.Parent = playerGui
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
	-- Le menu réimpose la souris à chaque image : sinon elle reste filmée au milieu de l'image
	MenuCursor.hide()
	UserInputService.MouseIconEnabled = false
	for _, info in match.actors do
		local actor = buildActor(session, rig, info)
		if actor then
			session.actors[info.id] = actor
		end
	end
	if gameHud then
		-- HUD de jeu de la partie, piloté par les évènements (créé au premier spawn en partie : peut manquer au menu)
		Speedometer.init()
		RoundHUD.show()
		setGameHudAlive(session, false)
		WeaponBar.setReplay({ tools = session.myTools, equipped = nil })
		AmmoCounter.setReplay({})
	end
	KillAnnouncer.restore(MatchRecordRules.streakAt(match, match.me, from))
	-- État en place au point de départ : armes, tenues, effets, actions, HUD (sans son ni effet)
	local events = match.events
	while session.nextEvent <= #events and events[session.nextEvent].t <= from do
		handleEvent(session, events[session.nextEvent], false)
		session.nextEvent += 1
	end
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, function(dt: number)
		render(session, dt)
	end)
end

-- Cette méthode permet de brancher le rejeu lorsque le client démarre (Studio seulement) : publication par le serveur
-- (MatchReplayReady), relance (MatchReplayRun), arrêt (MatchReplay retiré).
function MatchReplay.init(localPlayer: Player)
	if not RunService:IsStudio() then
		return
	end
	player = localPlayer
	-- Cette méthode permet de lancer le rejeu lorsque l'enregistrement demandé est prêt.
	local function tryStart()
		local name = player:GetAttribute(A.name)
		local ready = player:GetAttribute(A.ready)
		if type(name) == "string" and name ~= "" and ready == name then
			task.spawn(start, name)
		end
	end
	player:GetAttributeChangedSignal(A.ready):Connect(tryStart)
	player:GetAttributeChangedSignal(A.run):Connect(tryStart)
	player:GetAttributeChangedSignal(A.name):Connect(function()
		local name = player:GetAttribute(A.name)
		if type(name) ~= "string" or name == "" then
			MatchReplay.stop()
			cache = nil
		elseif cache and cache.name ~= name then
			cache = nil
		end
	end)
end

return MatchReplay
