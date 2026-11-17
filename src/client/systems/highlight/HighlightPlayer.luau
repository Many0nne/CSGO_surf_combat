-- Lecture du clip de la partie (#499) : après la bannière de résultat, la meilleure action de la manche est rejouée une
-- fois, sans possibilité de passer, dans la vraie map. Les personnages réels sont déjà détruits : des figurants (clones
-- de l'apparence gardée par le serveur, ReplicatedStorage.HighlightActors) suivent les positions enregistrées, avec
-- leur arme 3P (tenue posée par WeaponThirdPersonView, tag conservé) et leur animation de déplacement
-- (CharacterAnimator). La caméra est scriptée sur la prise du tireur (HighlightClipRules : POV recalé par le serveur),
-- avec le viewmodel de son arme et de son skin (changements d'arme rejoués avec la piste Equip), ses tirs (piste Shoot
-- et ses sons) ; les tirs des figurants sont
-- entendus en 3D, les victimes tombent en ragdoll (DeathRagdoll), chaque kill du tireur s'inscrit au kill feed (#534,
-- même rendu qu'en partie, sous la bande du haut). Tout est détruit à la fin (figurants, viewmodel,
-- sons, corps, interface, liaison de rendu).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local CharacterAnimator = require(ReplicatedStorage.Shared.CharacterAnimator)
local HighlightClipRules = require(ReplicatedStorage.Shared.HighlightClipRules)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ShotSoundRules = require(ReplicatedStorage.Shared.ShotSoundRules)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local WeaponSkins = require(ReplicatedStorage.Shared.WeaponSkins)
local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)
local AnimationSoundSystem = require(script.Parent.Parent.weapon.AnimationSoundSystem)
local DeathRagdoll = require(script.Parent.Parent.game.DeathRagdoll)
local ShotEffects = require(script.Parent.Parent.weapon.ShotEffects)
local SoundChannels = require(script.Parent.Parent.settings.SoundChannels)
local KillFeed = require(script.Parent.Parent.Parent.ui.KillFeed)
local UIKit = require(script.Parent.Parent.Parent.ui.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local HighlightPlayer = {}

-- Après la caméra FPS et le viewmodel du jeu (inactifs : personnage détruit)
local BIND_NAME = "HighlightReplay"
local ACTORS_FOLDER = "HighlightActors"
local ACTORS_WAIT = 3 -- s d'attente des figurants publiés par le serveur
local FADE = 0.3 -- s de fondu au noir à l'entrée et à la sortie
-- Une victime reste couchée (ragdoll) au moins ce temps (s) avant que sa piste puisse la remontrer (réapparition)
local DOWN_TIME = 1.5
-- Recul maximal (s) sur la piste d'une victime morte dans un trou de sa piste, pour y poser son corps
local LAST_ROW_WINDOW = 1
-- Vitesse verticale (studs/s) au-delà de laquelle un figurant est en l'air (saut, surf) pour son animation
local AIR_SPEED = 2
local BAR_HEIGHT = 0.1 -- part de l'écran de chaque bande noire du cadre cinéma
-- Kill feed du clip : à droite comme en partie, juste sous la bande noire du haut (px à l'échelle du HUD)
local FEED_MARGIN_RIGHT = 20
local FEED_MARGIN_TOP = 12

type Actor = {
	id: number,
	model: Model,
	root: BasePart,
	rows: { HighlightClipRules.Row },
	parts: { BasePart },
	decals: { Decal },
	animator: any?, -- CharacterAnimator
	visible: boolean,
	downAt: number?, -- instant (s du clip) de sa mort dans le clip
	lastPos: Vector3?,
	velocity: Vector3, -- vitesse sur sa piste à la dernière image (élan donné à son ragdoll)
}

-- Viewmodel d'une arme du tireur (préparé au début du clip, caché tant qu'elle n'est pas en main)
type Held = {
	model: Model,
	weapon: string, -- fiche WeaponConfig
	offset: CFrame,
	parts: { BasePart },
	tracks: { [string]: AnimationTrack },
}

type Session = {
	clip: HighlightClipRules.Clip,
	pov: { HighlightClipRules.Row },
	actors: { [number]: Actor },
	folder: Folder,
	gui: ScreenGui,
	fade: Frame,
	feed: KillFeed.Feed,
	equips: { HighlightClipRules.Equip },
	nextEquip: number,
	held: { [string]: Held }, -- par outil et skin
	viewmodel: Held?, -- arme en main (nil : mains vides)
	conns: { RBXScriptConnection },
	sounds: { Instance },
	elapsed: number,
	nextShot: number,
	nextKill: number,
	swing: number,
	onDone: () -> (),
	finished: boolean,
}

local current: Session? = nil

-- Cette méthode permet d'écrire une ligne préfixée dans la sortie de Studio lorsque la lecture avance (rien en jeu publié).
local function log(text: string)
	if RunService:IsStudio() then
		print("[Highlight] " .. text)
	end
end
local sample = table.create(6, 0) -- ligne interpolée de la caméra (réutilisée chaque image)
local actorSample = table.create(4, 0)

-- Cette méthode permet de trouver le Tool d'une arme (ReplicatedStorage.Tools) lorsque le clip désigne celle du tireur.
local function toolTemplate(toolName: string?): Tool?
	local tools = ReplicatedStorage:FindFirstChild("Tools")
	local tool = tools and toolName and tools:FindFirstChild(toolName)
	return if tool and tool:IsA("Tool") then tool else nil
end

-- Cette méthode permet de nommer le viewmodel d'une arme du tireur (outil et skin) lorsqu'il est préparé ou sorti.
local function heldKey(equip: HighlightClipRules.Equip): string
	return (equip.tool or "") .. "|" .. (equip.skinId or "")
end

-- Cette méthode permet de montrer ou cacher un viewmodel du tireur lorsqu'il sort ou range l'arme (caché par le
-- modificateur de transparence, comme ViewmodelSystem : les pistes restent chargées).
local function setHeldVisible(held: Held, visible: boolean)
	local modifier = if visible then 0 else 1
	for _, part in held.parts do
		part.LocalTransparencyModifier = modifier
	end
end

-- Cette méthode permet de préparer, caché devant la caméra, le viewmodel d'une arme du tireur (skin compris) lorsque
-- le clip démarre : clone du modèle de ReplicatedStorage.ViewModels, sans ombre, pistes chargées ; nil sans modèle.
local function buildViewmodel(camera: Camera, equip: HighlightClipRules.Equip): Held?
	local tool = toolTemplate(equip.tool)
	local viewmodelName = tool and tool:GetAttribute("ViewmodelName")
	if not tool or type(viewmodelName) ~= "string" or viewmodelName == "" then
		return nil
	end
	local container = ReplicatedStorage:FindFirstChild("ViewModels")
	local template = container and container:FindFirstChild(viewmodelName)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	if not model.PrimaryPart then
		local root = model:FindFirstChild("HumanoidRootPart")
		model.PrimaryPart = if root and root:IsA("BasePart")
			then root
			else model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not model.PrimaryPart then
		model:Destroy()
		return nil
	end
	local parts = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.CastShadow = false
			table.insert(parts, inst)
		end
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	if equip.skinId then
		WeaponSkins.apply(model, viewmodelName, equip.skinId)
	end
	local offset = tool:GetAttribute("ViewmodelOffset")
	local weapon = tool:GetAttribute("WeaponName")
	local held: Held = {
		model = model,
		weapon = if type(weapon) == "string" then weapon else tool.Name,
		offset = if typeof(offset) == "CFrame" then offset else CFrame.new(),
		parts = parts,
		tracks = {},
	}
	setHeldVisible(held, false)
	model:PivotTo(camera.CFrame * held.offset)
	model.Parent = camera
	local animator = AnimationSoundSystem.getAnimator(model)
	local folder = model:FindFirstChild("Animations") or model:FindFirstChild("AnimSaves")
	if animator and folder then
		for _, anim in folder:GetChildren() do
			if anim:IsA("Animation") then
				held.tracks[anim.Name] = animator:LoadAnimation(anim)
			end
		end
	end
	local idle = held.tracks.Idle
	if idle then
		idle.Looped = true
		idle.Priority = Enum.AnimationPriority.Idle
	end
	return held
end

-- Cette méthode permet de mettre une arme en main du tireur lorsque le clip y arrive : l'arme précédente est rangée
-- (pistes coupées, cachée), la nouvelle montrée avec sa boucle Idle et, pour un changement en cours de clip (`animate`),
-- sa piste Equip et ses sons, comme en jeu (ViewmodelSystem) ; mains vides si l'arme n'a pas de viewmodel.
local function equipHeld(session: Session, equip: HighlightClipRules.Equip, animate: boolean)
	local held = session.held[heldKey(equip)]
	if held == session.viewmodel then
		return
	end
	local previous = session.viewmodel
	if previous then
		for _, track in previous.tracks do
			track:Stop(0)
		end
		setHeldVisible(previous, false)
	end
	session.viewmodel = held
	session.swing = 0
	if not held then
		return
	end
	setHeldVisible(held, true)
	local idle = held.tracks.Idle
	if idle then
		idle:Play(0)
	end
	local equipTrack = held.tracks.Equip
	if animate and equipTrack then
		equipTrack.Looped = false
		equipTrack:Play(0)
		local cfg = WeaponConfig.Weapons[held.weapon]
		local sounds = cfg and cfg.AnimationSounds and cfg.AnimationSounds.Equip or {}
		for _, conn in AnimationSoundSystem.connectSoundMarkers(equipTrack, held.model, sounds) do
			table.insert(session.conns, conn)
		end
	end
end

-- Cette méthode permet de jouer le tir (ou le coup de couteau) du tireur dans le viewmodel lorsque le clip y arrive :
-- piste Shoot et ses sons à marqueurs (WeaponConfig.AnimationSounds), comme en jeu ; un coup de couteau qui tue sonne
-- « Shoot_human », sinon « Shoot_void ».
local function playOwnShot(session: Session, lethal: boolean)
	local held = session.viewmodel
	if not held then
		return
	end
	local model = held.model
	local cfg = WeaponConfig.Weapons[held.weapon]
	local name = "Shoot"
	if cfg and cfg.IsMelee and cfg.ShootAnimations and #cfg.ShootAnimations > 0 then
		session.swing = session.swing % #cfg.ShootAnimations + 1
		name = cfg.ShootAnimations[session.swing]
	end
	local track = held.tracks[name]
	if not track then
		return
	end
	track.Looped = false
	track:Stop(0)
	track:Play(if cfg then cfg.AttackFadeTime else nil)
	local sounds = cfg and cfg.AnimationSounds and cfg.AnimationSounds[name] or {}
	for _, conn in AnimationSoundSystem.connectSoundMarkers(track, model, sounds) do
		table.insert(session.conns, conn)
	end
	if cfg and cfg.IsMelee then
		local conn = AnimationSoundSystem.connectSoundMarker(
			track,
			model,
			"Stab Sound",
			if lethal then "Shoot_human" else "Shoot_void"
		)
		if conn then
			table.insert(session.conns, conn)
		end
	end
end

-- Cette méthode permet de faire entendre en 3D le tir d'un figurant lorsque le clip y arrive : copie du son de tir de
-- son arme 3P, jouée sur la poignée (le figurant vit jusqu'à la fin du clip).
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

-- Cette méthode permet de montrer ou cacher un figurant lorsqu'il entre dans sa piste ou en sort (mort, réapparition).
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

-- Cette méthode permet de créer le figurant d'un participant lorsque le clip se prépare : clone de son apparence publiée
-- par le serveur, posé hors champ et caché jusqu'à sa première position ; nil sans apparence ou piste lisible.
local function buildActor(session: Session, source: Instance, entry: { id: number, track: string }): Actor?
	local template = source:FindFirstChild(tostring(entry.id))
	local rows =
		HighlightClipRules.decodeSeries(entry.track, HighlightClipRules.ACTOR_SCALES, HighlightClipRules.ACTOR_HZ * 20)
	if not (template and template:IsA("Model")) or not rows then
		return nil
	end
	local model = template:Clone()
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end
	local parts, decals = {}, {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		elseif inst:IsA("Decal") then
			table.insert(decals, inst)
		end
	end
	model.Parent = session.folder
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local actor: Actor = {
		id = entry.id,
		model = model,
		root = root,
		rows = rows,
		parts = parts,
		decals = decals,
		animator = if humanoid then CharacterAnimator.new(humanoid) else nil,
		visible = true,
		velocity = Vector3.zero,
	}
	setVisible(actor, false)
	return actor
end

-- Cette méthode permet de placer chaque figurant à l'instant t du clip lorsqu'une image est rendue : position et cap
-- interpolés, animation de déplacement d'après sa vitesse, caché hors de sa piste et pendant sa mort.
local function placeActors(session: Session, t: number, dt: number)
	for _, actor in session.actors do
		local present = HighlightClipRules.sampleRows(actor.rows, HighlightClipRules.ACTOR_HZ, t, actorSample, 4)
		local down = actor.downAt ~= nil and t >= actor.downAt and t < actor.downAt + DOWN_TIME
		if not present or down then
			setVisible(actor, false)
			actor.lastPos = nil
			continue
		end
		local pos = Vector3.new(actorSample[1], actorSample[2], actorSample[3])
		actor.root.CFrame = CFrame.new(pos) * CFrame.Angles(0, actorSample[4], 0)
		local reborn = not actor.visible
		setVisible(actor, true)
		if reborn and actor.downAt and t >= actor.downAt then
			-- Réapparu dans le clip : le ragdoll a masqué ses pièces, montrées de nouveau par setVisible
			actor.downAt = nil
		end
		local velocity = if actor.lastPos and dt > 0 then (pos - actor.lastPos) / dt else Vector3.zero
		actor.lastPos = pos
		actor.velocity = velocity
		if actor.animator then
			local airborne = math.abs(velocity.Y) > AIR_SPEED
			actor.animator:update({
				onGround = not airborne,
				crouching = false,
				surfing = false,
				speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude,
				verticalSpeed = velocity.Y,
			})
		end
	end
end

-- Cette méthode permet de poser un figurant caché sur sa dernière position connue avant t (au plus LAST_ROW_WINDOW s
-- plus tôt) lorsqu'il meurt dans un trou de sa piste ; il redevient visible, sinon rien ne change.
local function placeAtLastRow(actor: Actor, t: number)
	if actor.downAt then
		return
	end
	local hz = HighlightClipRules.ACTOR_HZ
	local last = math.clamp(math.floor(t * hz) + 1, 1, #actor.rows)
	for i = last, math.max(1, last - math.ceil(LAST_ROW_WINDOW * hz)), -1 do
		local row = actor.rows[i]
		if row then
			actor.root.CFrame = CFrame.new(row[1], row[2], row[3]) * CFrame.Angles(0, row[4], 0)
			actor.velocity = Vector3.zero
			setVisible(actor, true)
			return
		end
	end
end

-- Cette méthode permet de détruire tout ce que le clip a créé (liaison de rendu, connexions, figurants et leurs
-- animateurs, viewmodel, sons, corps, interface) lorsqu'il se termine ou est interrompu.
local function cleanup(session: Session)
	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, conn in session.conns do
		conn:Disconnect()
	end
	table.clear(session.conns)
	for _, actor in session.actors do
		if actor.animator then
			actor.animator:destroy()
		end
	end
	table.clear(session.actors)
	for _, sound in session.sounds do
		sound:Destroy()
	end
	table.clear(session.sounds)
	for _, held in session.held do
		for _, track in held.tracks do
			track:Stop(0)
		end
		held.model:Destroy()
	end
	table.clear(session.held)
	session.viewmodel = nil
	session.folder:Destroy()
	KillFeed.destroy(session.feed)
	session.gui:Destroy()
	DeathRagdoll.clear()
end

-- Cette méthode permet de terminer la lecture (une seule fois) lorsqu'elle arrive au bout ou que l'état du jeu la coupe :
-- tout est nettoyé, puis `onDone` enchaîne la suite (manche suivante).
local function finish(session: Session)
	if session.finished then
		return
	end
	session.finished = true
	if current == session then
		current = nil
	end
	log(string.format("lecture finie à %.2f s sur %.2f s", session.elapsed, session.clip.duration))
	cleanup(session)
	task.spawn(session.onDone)
end

-- Cette méthode permet de rendre une image du clip lorsqu'il tourne : caméra du tireur, viewmodel, figurants, tirs,
-- morts, fondus ; au bout de la durée, la lecture se termine.
local function render(session: Session, dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local clip = session.clip
	session.elapsed += dt
	local t = session.elapsed
	if HighlightClipRules.sampleRows(session.pov, HighlightClipRules.POV_HZ, t, sample) then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.new(sample[1], sample[2] + sample[4], sample[3])
			* CFrame.Angles(0, math.rad(-sample[5]), 0)
			* CFrame.Angles(math.rad(sample[6]), 0, 0)
	end
	while session.nextEquip <= #session.equips and session.equips[session.nextEquip].t <= t do
		equipHeld(session, session.equips[session.nextEquip], session.nextEquip > 1)
		session.nextEquip += 1
	end
	local held = session.viewmodel
	if held then
		held.model:PivotTo(camera.CFrame * held.offset)
	end
	placeActors(session, t, dt)
	while session.nextShot <= #clip.shots and clip.shots[session.nextShot].t <= t do
		local shot = clip.shots[session.nextShot]
		session.nextShot += 1
		local dir = if typeof(shot.dir) == "Vector3" then shot.dir else nil
		if shot.id == clip.killerId then
			local lethal = false
			for _, kill in clip.kills do
				if kill.t >= shot.t and kill.t - shot.t < 0.5 then
					lethal = true
				end
			end
			playOwnShot(session, lethal)
			if dir then
				local model = if session.viewmodel then session.viewmodel.model else nil
				ShotEffects.playReplay(model, camera.CFrame.Position, dir, { session.folder, camera })
			end
		else
			local actor = session.actors[shot.id]
			if actor and actor.visible then
				playActorShot(session, actor)
				if dir then
					local gun = actor.model:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
					local eye = actor.root.Position + Vector3.new(0, HighlightClipRules.DEFAULT_EYE, 0)
					ShotEffects.playReplay(gun, eye, dir, { session.folder, camera }, camera.CFrame.Position)
				end
			end
		end
	end
	while session.nextKill <= #clip.kills and clip.kills[session.nextKill].t <= t do
		local kill = clip.kills[session.nextKill]
		session.nextKill += 1
		KillFeed.push(session.feed, HighlightClipRules.killFeedLine(clip, kill))
		local actor = session.actors[kill.victimId]
		local wasVisible = actor ~= nil and actor.visible
		if actor and not actor.visible then
			-- Piste trouée à l'instant de la mort : le corps tombe de la dernière position connue juste avant
			placeAtLastRow(actor, kill.t)
		end
		if actor and actor.visible then
			local weapon = if type(kill.weapon) == "string" then kill.weapon else clip.weapon
			DeathRagdoll.spawn(actor.model, kill.direction, weapon, kill.headshot, actor.velocity)
			setVisible(actor, false)
			actor.downAt = kill.t
		end
		log(
			string.format(
				"kill à %.2f s : victime %d, figurant %s, %s",
				kill.t,
				kill.victimId,
				if actor then "présent" else "absent",
				if wasVisible then "visible" elseif actor and actor.downAt == kill.t then "repris" else "sans corps"
			)
		)
	end
	local remaining = clip.duration - t
	session.fade.BackgroundTransparency = math.clamp(math.min(t, remaining) / FADE, 0, 1)
	if t >= clip.duration then
		finish(session)
	end
end

-- Cette méthode permet de construire l'interface du clip lorsqu'il démarre : bandes noires du cadre cinéma, titre
-- « MEILLEURE ACTION » et nom du tireur, kill feed vide (à l'échelle du HUD), voile de fondu (noir d'abord).
local function buildGui(clip: HighlightClipRules.Clip): (ScreenGui, Frame, KillFeed.Feed)
	local gui = UIKit.create("ScreenGui", {
		Name = "HighlightClip",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 40,
	}) :: ScreenGui
	for _, top in { true, false } do
		UIKit.frame({
			Name = if top then "TopBar" else "BottomBar",
			AnchorPoint = Vector2.new(0, if top then 0 else 1),
			Position = UDim2.fromScale(0, if top then 0 else 1),
			Size = UDim2.fromScale(1, BAR_HEIGHT),
			BackgroundColor3 = C.Black,
			Parent = gui,
		})
	end
	local caption = UIKit.frame({
		Name = "Caption",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 32, 1, -16),
		Size = UDim2.new(1, -64, BAR_HEIGHT, -16),
		ZIndex = 2,
		Parent = gui,
	})
	UIKit.accentLabel(caption, {
		Name = "Title",
		Text = "MEILLEURE ACTION",
		Size = UDim2.new(1, 0, 0, 20),
	})
	local _, shadow = UIKit.shadowedText(caption, {
		Name = "Killer",
		Text = string.upper(clip.killerName),
		FontFace = F.Display,
		TextSize = 30,
		TextColor3 = C.Bone,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 3,
	}, 2)
	shadow.ZIndex = 2
	local feed =
		KillFeed.mount(UIKit.scaledRoot(gui, true), UDim2.new(1, -FEED_MARGIN_RIGHT, BAR_HEIGHT, FEED_MARGIN_TOP))
	local fade = UIKit.frame({
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 0,
		ZIndex = 10,
		Parent = gui,
	})
	return gui, fade, feed
end

-- Cette méthode permet de savoir si un clip est en cours de lecture lorsque l'état du jeu change.
function HighlightPlayer.isPlaying(): boolean
	return current ~= nil
end

-- Cette méthode permet d'interrompre la lecture en cours lorsque le joueur quitte la phase de résultat (rien sinon) ;
-- `onDone` n'est pas appelé deux fois.
function HighlightPlayer.stop()
	local session = current
	if session then
		session.onDone = function() end
		finish(session)
	end
end

-- Cette méthode permet de rejouer le clip de la partie lorsque la bannière de résultat se ferme ; `onDone` est appelé
-- une fois la lecture finie (ou impossible : clip illisible), après le nettoyage. Sans possibilité de passer.
function HighlightPlayer.play(clip: HighlightClipRules.Clip, onDone: () -> ())
	HighlightPlayer.stop()
	local pov = HighlightClipRules.decodeSeries(
		clip.pov,
		HighlightClipRules.POV_SCALES,
		HighlightClipRules.POV_HZ * (HighlightClipRules.MAX_DURATION + 2)
	)
	local camera = workspace.CurrentCamera
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not pov or #pov < 2 or not camera or not playerGui then
		log("clip illisible : lecture sautée")
		task.spawn(onDone)
		return
	end
	local gui, fade, feed = buildGui(clip)
	gui.Parent = playerGui
	local folder = Instance.new("Folder")
	folder.Name = "HighlightReplay"
	folder.Parent = workspace
	local session: Session = {
		clip = clip,
		pov = pov,
		actors = {},
		folder = folder,
		gui = gui,
		fade = fade,
		feed = feed,
		equips = HighlightClipRules.equipTimeline(clip),
		nextEquip = 1,
		held = {},
		viewmodel = nil,
		conns = {},
		sounds = {},
		elapsed = 0,
		nextShot = 1,
		nextKill = 1,
		swing = 0,
		onDone = onDone,
		finished = false,
	}
	current = session
	table.sort(clip.shots, function(a, b)
		return a.t < b.t
	end)
	table.sort(clip.kills, function(a, b)
		return a.t < b.t
	end)
	-- Filet : la lecture se termine même si le rendu s'arrête (fenêtre en arrière-plan)
	task.delay(clip.duration + HighlightClipRules.CLIP_MARGIN + 2, finish, session)
	task.spawn(function()
		-- Figurants publiés par le serveur avec le résultat (dossier répliqué)
		local source = ReplicatedStorage:WaitForChild(ACTORS_FOLDER, ACTORS_WAIT)
		if session.finished then
			return
		end
		if source then
			for _, entry in clip.actors do
				local actor = if source:WaitForChild(tostring(entry.id), ACTORS_WAIT)
					then buildActor(session, source, entry)
					else nil
				if session.finished then
					return
				end
				if actor then
					session.actors[entry.id] = actor
				end
			end
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = CameraConfig.DEFAULT_FOV
		-- Toutes les armes du clip préparées d'avance : un changement d'arme ne clone rien pendant la lecture
		local weapons = {}
		for _, equip in session.equips do
			local key = heldKey(equip)
			if equip.tool and not session.held[key] then
				local held = buildViewmodel(camera, equip)
				if held then
					session.held[key] = held
					table.insert(weapons, held.model.Name)
				end
			end
		end
		local built = 0
		for _ in session.actors do
			built += 1
		end
		log(
			string.format(
				"lecture : %s, %.1f s, %d/%d figurant(s), viewmodel(s) %s, %d changement(s) d'arme, POV %s",
				clip.killerName,
				clip.duration,
				built,
				#clip.actors,
				if #weapons > 0 then table.concat(weapons, ", ") else "aucun",
				#session.equips - 1,
				if clip.degraded then "serveur" else "du client"
			)
		)
		render(session, 0)
		RunService:BindToRenderStep(
			BIND_NAME,
			Enum.RenderPriority.Camera.Value + 3,
			PerfMarkers.wrap("clip de la partie", function(dt: number)
				render(session, dt)
			end)
		)
	end)
end

return HighlightPlayer
