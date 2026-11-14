-- Lecteur des démos rejouées de l'écran Apprendre (#285). Un clip (ui/DemoClips, format DemoClipRules) est rejoué
-- en boucle, en vue 1re personne depuis la caméra enregistrée, dans un ViewportFrame qui contient une copie des pièces de
-- la map autour des trajectoires des clips : ni le personnage, ni la caméra du joueur, ni la map jouée ne sont touchés.
-- Par-dessus : légende du geste, et ce que font les mains au même instant (touches en keycaps du HUD, KeyDisplay ;
-- rotation de la souris ; vitesse au style du compteur, HUDRules). La copie de la map est construite à la première
-- lecture, gardée tant que le lecteur vit, et détruite avec lui (`destroy`, appelé dès qu'on quitte l'onglet ou l'écran).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CameraConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CameraConfig"))
local PerfMarkers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PerfMarkers"))
local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local DemoClipRules = require(script.Parent.DemoClipRules)
local HUDRules = require(script.Parent.HUDRules)
local KeyDisplay = require(script.Parent.KeyDisplay)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local DemoPlayer = {}

-- Cadre du clip (px à 720 de haut), au format 16:9 du jeu : même FOV vertical que la caméra du joueur
DemoPlayer.Size = Vector2.new(640, 360)

local COPY_DISTANCE = 450 -- studs autour d'un point de passage (le décor lointain des rampes reste visible)
local PATH_EVERY = 15 -- un point de passage tous les n échantillons (0,5 s à 30 Hz)
local COPY_BATCH = 1500 -- pièces parcourues entre deux images pendant la copie
local FREE_BATCH = 2000 -- pièces détruites entre deux images à la fermeture
local LOOP_FADE = 0.35 -- secondes de fondu au noir de part et d'autre du point de bouclage
local KEYS_SCALE = 0.8
local MARGIN = 16
local BAND_WIDTH = 150
local TURN_TRACK = 64 -- px de chaque demi-barre de la souris
local TURN_HOT = 0.75 -- part de l'indicateur au-delà de laquelle il passe au rouge d'impact
local SKY_TOP = Color3.fromRGB(58, 92, 140)
local SKY_HORIZON = Color3.fromRGB(196, 186, 168)

export type Demo = {
	frame: Frame,
	play: (id: string, title: string, caption: string) -> (),
	destroy: () -> (),
}

-- Clips décodés, par id (données fixes : gardées pour toute la session)
local decoded: { [string]: DemoClipRules.Clip | false } = {}

-- Cette méthode permet de charger et décoder le module de données d'un clip (ui/DemoClips/<Id>) lorsque le lecteur en a
-- besoin ; false si le module manque ou s'il est abîmé (raison écrite une fois dans la console).
local function loadClip(id: string): DemoClipRules.Clip?
	local cached = decoded[id]
	if cached ~= nil then
		return cached or nil
	end
	local folder = script.Parent:FindFirstChild("DemoClips")
	local moduleName = string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2)
	local module = folder and folder:FindFirstChild(moduleName)
	local clip: DemoClipRules.Clip? = nil
	if module and module:IsA("ModuleScript") then
		local ok, text = pcall(require, module)
		if not ok then
			warn("[DemoPlayer] clip " .. id .. " : module en erreur : " .. tostring(text))
		elseif type(text) ~= "string" then
			warn("[DemoPlayer] clip " .. id .. " : le module doit renvoyer un texte, pas " .. typeof(text))
		else
			local result, why = DemoClipRules.decode(text)
			clip = result
			if not result then
				warn("[DemoPlayer] clip " .. id .. " illisible : " .. tostring(why))
			end
		end
	end
	decoded[id] = clip or false
	return clip
end

-- Cette méthode permet de copier une pièce de la map, sans physique ni pièce enfant, lorsque le décor du lecteur se
-- construit (les Decal, Texture et SurfaceAppearance restent).
local function copyPart(part: BasePart, parent: Instance)
	local copy = part:Clone()
	if not copy then
		return -- Archivable = false : pas de copie possible
	end
	for _, child in copy:GetDescendants() do
		if
			child:IsA("BasePart")
			or child:IsA("JointInstance")
			or child:IsA("Constraint")
			or child:IsA("LuaSourceContainer")
			or child:IsA("Light")
			or child:IsA("Sound")
			or child:IsA("ParticleEmitter")
			or child:IsA("Beam")
			or child:IsA("Trail")
		then
			child:Destroy()
		end
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Parent = parent
end

-- Cette méthode permet de détruire une copie du décor par lots sur plusieurs images lorsque le lecteur s'en sépare
-- (fermeture, ou copie interrompue) : d'un coup, ses 17 000 pièces faisaient une image de plus de 100 ms ; `after`
-- (le cadre du lecteur) est détruit ensuite.
local function freeInBatches(model: Instance, after: Instance?)
	task.spawn(function()
		for i, part in model:GetChildren() do
			part:Destroy()
			if i % FREE_BATCH == 0 then
				task.wait()
			end
		end
		model:Destroy()
		if after then
			after:Destroy()
		end
	end)
end

-- Cette méthode permet de poser un dégradé vertical de transparence sur un fond lorsque la légende ou les mains doivent
-- rester lisibles sur la scène : opaque (`opacity`) au bord haut (`top`) ou bas du cadre, effacé vers le milieu.
local function fadeBand(parent: GuiObject, name: string, top: boolean, height: number, opacity: number): Frame
	local band = UIKit.frame({
		Name = name,
		AnchorPoint = Vector2.new(0, if top then 0 else 1),
		Position = UDim2.fromScale(0, if top then 0 else 1),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = C.Scrim,
		ZIndex = 4,
		Parent = parent,
	})
	local solid, clear = 1 - opacity, 1
	UIKit.create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(if top then solid else clear, if top then clear else solid),
		Parent = band,
	})
	return band
end

-- Cette méthode permet de construire le lecteur dans `parent` lorsque l'écran Apprendre s'affiche ; rien n'est copié de
-- la map avant le premier `play`, qui copie alors le décor autour des trajectoires de tous les clips `clipIds`.
function DemoPlayer.new(parent: GuiObject, layoutOrder: number, clipIds: { string }): Demo
	local frame = UIKit.frame({
		Name = "Demo",
		Size = UDim2.fromOffset(DemoPlayer.Size.X, DemoPlayer.Size.Y),
		BackgroundColor3 = C.Black,
		ClipsDescendants = true,
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
	local sky = UIKit.frame({ Name = "Sky", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White, Parent = frame })
	UIKit.create("UIGradient", { Rotation = 90, Color = ColorSequence.new(SKY_TOP, SKY_HORIZON), Parent = sky })

	local viewport = UIKit.create("ViewportFrame", {
		Name = "View",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(190, 178, 190), -- ombre bleutée du couchant, assez claire sans ombres portées
		LightColor = Color3.fromRGB(255, 214, 170), -- soleil bas et chaud de Dizzy
		LightDirection = -Lighting:GetSunDirection(),
		ZIndex = 2,
		Parent = frame,
	}) :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.FieldOfView = CameraConfig.DEFAULT_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local fade = UIKit.frame({
		Name = "LoopFade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = frame,
	})

	-- Légende : nom du geste en ambre, geste en une ligne
	fadeBand(frame, "TopBand", true, 86, 0.75)
	local topic, topicShadow = UIKit.accentLabel(frame, {
		Name = "Topic",
		Position = UDim2.fromOffset(MARGIN, 10),
		Size = UDim2.new(1, -2 * MARGIN, 0, 20),
		ZIndex = 6,
	})
	topicShadow.ZIndex = 5
	local caption, captionShadow = UIKit.shadowedText(frame, {
		Name = "Caption",
		FontFace = F.DisplayText,
		TextSize = 18,
		TextColor3 = C.Bone,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(MARGIN, 32),
		Size = UDim2.new(1, -2 * MARGIN, 0, 44),
		ZIndex = 6,
	}, 1)
	captionShadow.ZIndex = 5

	-- Message au centre (chargement, clip absent)
	local message, messageShadow = UIKit.shadowedText(frame, {
		Name = "Message",
		FontFace = F.Display,
		TextSize = 22,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	}, 2)
	messageShadow.ZIndex = 5

	-- Mains : vitesse à gauche, touches au centre, souris à droite
	fadeBand(frame, "BottomBand", false, 130, 0.8)
	local hands = UIKit.frame({
		Name = "Hands",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = frame,
	})

	local speedValue, speedShadow = UIKit.shadowedText(hands, {
		Name = "Speed",
		Text = "0",
		FontFace = F.Display,
		TextSize = 40,
		TextColor3 = C.Bone,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN, 1, -MARGIN - 14),
		Size = UDim2.fromOffset(84, 44),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
	}, 2)
	speedShadow.ZIndex = 1
	local tierLabel, tierShadow = UIKit.accentLabel(hands, {
		Name = "Tier",
		Text = HUDRules.SPEED_TIERS[1].name,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN + 92, 1, -MARGIN - 34),
		Size = UDim2.fromOffset(70, 18),
	})
	UIKit.accentLabel(hands, {
		Name = "Unit",
		Text = "U/S",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN + 92, 1, -MARGIN - 16),
		Size = UDim2.fromOffset(40, 18),
	})
	local band = UIKit.frame({
		Name = "Band",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN, 1, -MARGIN),
		Size = UDim2.fromOffset(BAND_WIDTH, 6),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.7,
		ZIndex = 2,
		Parent = hands,
	})
	local bandFill =
		UIKit.frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, Parent = band })

	-- Touches : mêmes keycaps que l'affichage des touches du HUD (mode simple : directions et saut)
	local gridWidth, gridHeight = HUDRules.keyDisplayGridSize("simple")
	local keys = UIKit.frame({
		Name = "Keys",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -MARGIN),
		Size = UDim2.fromOffset(gridWidth, gridHeight),
		Parent = hands,
	})
	UIKit.create("UIScale", { Scale = KEYS_SCALE, Parent = keys })
	local caps: { { id: string, paint: (boolean) -> (), down: boolean } } = {}
	for _, entry in HUDRules.keyDisplayEntries("simple") do
		local _, paintKey = KeyDisplay.buildKeycap(keys, entry)
		table.insert(caps, { id = entry.id, paint = paintKey, down = false })
	end

	-- Souris : icône au centre, demi-barre remplie du côté où elle tourne, d'autant plus qu'elle tourne vite
	local mouse = UIKit.frame({
		Name = "Mouse",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -MARGIN, 1, -MARGIN),
		Size = UDim2.fromOffset(2 * TURN_TRACK + 36, 60),
		Parent = hands,
	})
	UIKit.accentLabel(mouse, {
		Name = "MouseLabel",
		Text = "SOURIS",
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
	})
	local icon = UIKit.mouseIcon(mouse, "wheelClick", C.Bone)
	icon.AnchorPoint = Vector2.new(0.5, 1)
	icon.Position = UDim2.fromScale(0.5, 1)
	local fills = {}
	for _, side in { -1, 1 } do
		local track = UIKit.frame({
			Name = if side < 0 then "TurnLeft" else "TurnRight",
			AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5),
			Position = UDim2.new(0.5, side * 14, 1, -17),
			Size = UDim2.fromOffset(TURN_TRACK, 8),
			BackgroundColor3 = C.Bone,
			BackgroundTransparency = 0.7,
			Parent = mouse,
		})
		fills[side] = UIKit.frame({
			Name = "Fill",
			AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0),
			Position = UDim2.fromScale(if side < 0 then 1 else 0, 0),
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = C.Accent,
			Parent = track,
		})
	end

	-- Avancement dans la boucle, au ras du bas du cadre
	local progress = UIKit.frame({
		Name = "Progress",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(0, 2),
		BackgroundColor3 = C.Accent,
		ZIndex = 7,
		Parent = frame,
	})

	local alive = true
	local scene: Model? = nil -- copie de la map, construite une fois
	local building = false
	local clip: DemoClipRules.Clip? = nil
	local elapsed = 0
	local conn: RBXScriptConnection? = nil
	local shownSpeed, shownTier = -1, 0

	-- Cette méthode permet d'afficher un message au centre du cadre (chargement, clip absent) lorsque rien n'est rejoué ;
	-- nil le retire et montre les mains.
	local function setMessage(text: string?)
		message.Text = text or ""
		messageShadow.Text = text or ""
		hands.Visible = text == nil
		progress.Visible = text == nil
	end

	-- Cette méthode permet de peindre la vitesse au style du compteur du HUD lorsqu'elle change d'une unité.
	local function paintSpeed(speed: number)
		local shown = math.floor(speed)
		if shown == shownSpeed then
			return
		end
		shownSpeed = shown
		speedValue.Text = tostring(shown)
		speedShadow.Text = tostring(shown)
		bandFill.Size = UDim2.fromScale(HUDRules.speedFill(speed), 1)
		local tier = HUDRules.speedTier(speed)
		if tier ~= shownTier then
			shownTier = tier
			local hot = tier == #HUDRules.SPEED_TIERS
			tierLabel.Text = HUDRules.SPEED_TIERS[tier].name
			tierShadow.Text = tierLabel.Text
			tierLabel.TextColor3 = if hot then C.HitRed else C.Accent
			speedValue.TextColor3 = if hot then C.HitRed else C.Bone
			bandFill.BackgroundColor3 = if hot then C.HitRed else C.Accent
		end
	end

	-- Cette méthode permet de rendre l'image du clip à l'instant courant lorsque le lecteur tourne : caméra, touches,
	-- souris, vitesse, fondu de bouclage, avancement.
	local function render(dt: number)
		local current = clip
		if not current then
			return
		end
		local duration = DemoClipRules.duration(current)
		elapsed = DemoClipRules.loopTime(elapsed + dt, duration)
		local state = DemoClipRules.sampleAt(current, elapsed)
		local eye = Vector3.new(state.x, state.y + state.eye, state.z)
		-- Même composition que FPSCamera : lacet puis tangage
		camera.CFrame = CFrame.new(eye)
			* CFrame.Angles(0, math.rad(-state.yaw), 0)
			* CFrame.Angles(math.rad(state.pitch), 0, 0)
		for _, cap in caps do
			local down = DemoClipRules.isHeld(state.keys, cap.id)
			if down ~= cap.down then
				cap.down = down
				cap.paint(down)
			end
		end
		local fill = DemoClipRules.turnFill(state.turn)
		local hot = math.abs(fill) >= TURN_HOT
		for side, bar in fills do
			local amount = if fill * side > 0 then math.abs(fill) else 0
			bar.Size = UDim2.fromScale(amount, 1)
			bar.BackgroundColor3 = if hot then C.HitRed else C.Accent
		end
		paintSpeed(state.speed)
		fade.BackgroundTransparency = 1 - DemoClipRules.loopFade(elapsed, duration, LOOP_FADE)
		progress.Size = UDim2.new(elapsed / duration, 0, 0, 2)
	end

	-- Cette méthode permet de copier les pièces de la map autour des trajectoires de tous les clips lorsque la première
	-- lecture commence, sur plusieurs images ; s'arrête si le lecteur est détruit entre-temps.
	local function buildScene(clips: { DemoClipRules.Clip }, onReady: () -> ())
		if scene or building then
			return
		end
		local maps = workspace:FindFirstChild("Maps")
		local map = maps and maps:FindFirstChild(clips[1].map)
		if not map then
			setMessage("MAP " .. clips[1].map .. " ABSENTE")
			return
		end
		building = true
		local points = {}
		for _, each in clips do
			for _, point in DemoClipRules.pathPoints(each, PATH_EVERY) do
				table.insert(points, point)
			end
		end
		local model = Instance.new("Model")
		model.Name = "Scene"
		task.spawn(function()
			local started = os.clock()
			local copied = 0
			local ok, err = pcall(function()
				for i, part in map:GetDescendants() do
					if i % COPY_BATCH == 0 then
						task.wait()
						if not alive then
							return
						end
					end
					if
						part:IsA("BasePart")
						and part.Transparency < 1
						and DemoClipRules.nearPath(part.Position, part.Size.Magnitude / 2, points, COPY_DISTANCE)
					then
						copyPart(part, model)
						copied += 1
					end
				end
			end)
			if not ok then
				warn("[DemoPlayer] copie du décor impossible : " .. tostring(err))
				freeInBatches(model)
				building = false
				if alive then
					setMessage("DÉCOR INDISPONIBLE")
				end
				return
			end
			if not alive then
				freeInBatches(model)
				return
			end
			model.Parent = viewport
			scene = model
			building = false
			if RunService:IsStudio() then
				print(
					string.format("[DemoPlayer] décor : %d pièces copiées en %.2f s", copied, os.clock() - started)
				)
			end
			onReady()
		end)
	end

	-- Cette méthode permet de couper la boucle de rendu et de masquer la vue lorsque rien n'est rejoué (clip absent,
	-- décor en cours de copie) : pas d'image figée d'un clip précédent derrière le message.
	local function pause()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		viewport.Visible = false
	end

	-- Cette méthode permet de rejouer le clip choisi lorsque le décor est prêt : vue, mains et boucle de rendu.
	local function resume()
		if not (alive and clip and scene) then
			return
		end
		setMessage(nil)
		viewport.Visible = true
		if not conn then
			conn = RunService.RenderStepped:Connect(PerfMarkers.wrap("démo apprendre", render))
		end
		render(0)
	end

	-- Cette méthode permet de lancer la lecture en boucle d'un clip lorsque le joueur le choisit dans le sélecteur ; la
	-- première lecture copie d'abord le décor, puis rejoue le clip choisi entre-temps.
	local function play(id: string, title: string, text: string)
		topic.Text = title
		topicShadow.Text = title
		caption.Text = text
		captionShadow.Text = text
		local chosen = loadClip(id)
		clip = chosen
		elapsed = 0
		shownSpeed, shownTier = -1, 0
		if not chosen then
			pause()
			setMessage("CLIP À ENREGISTRER")
			return
		end
		if scene then
			resume()
			return
		end
		pause()
		setMessage("CHARGEMENT…")
		local clips = { chosen }
		for _, other in clipIds do
			local loaded = if other ~= id then loadClip(other) else nil
			if loaded and loaded.map == chosen.map then
				table.insert(clips, loaded)
			end
		end
		buildScene(clips, resume)
	end

	-- Cette méthode permet d'arrêter la lecture et de libérer le cadre, la copie de la map et la connexion de rendu
	-- lorsque le joueur quitte l'écran Apprendre ; la copie est détruite par lots (freeInBatches).
	local function destroy()
		alive = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
		clip = nil
		frame.Visible = false
		local built = scene
		scene = nil
		if built then
			freeInBatches(built, frame)
		else
			frame:Destroy()
		end
	end

	setMessage("CHARGEMENT…")
	return { frame = frame, play = play, destroy = destroy }
end

return DemoPlayer
