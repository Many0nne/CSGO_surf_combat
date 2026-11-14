-- ClipRecorder.luau (client)
-- Enregistreur des démos de l'écran Infos > SURFER (#285), actif uniquement dans Studio. L'attribut joueur
-- `DebugClipRecorder` (nom du clip : "surf", "bhop", "strafe", "chain") l'arme ; F7 lance puis arrête la prise. Il lit
-- seulement : position de la racine, caméra (hauteur, lacet et tangage de FPSCamera), touches de mouvement tenues
-- (KeyBindings), vitesse horizontale (MovementController.getVelocity). Il ne touche ni au mouvement ni à la caméra.
-- Échantillons à pas fixe (DemoClipRules, HZ), placés entre deux images rendues par interpolation. À l'arrêt, le clip
-- encodé est rangé dans `Player.DebugClips.<nom>` (StringValue locale, lue par le MCP en contexte Client) : procédure
-- d'extraction dans docs/ui.md, « Démos rejouées ».

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local KeyBindings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KeyBindings"))
local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local DemoClipRules = require(script.Parent.Parent.ui.DemoClipRules)

local ATTRIBUTE = "DebugClipRecorder"
local TOGGLE_KEY = Enum.KeyCode.F7
local HZ = 30
local MAX_SECONDS = 30 -- prise arrêtée d'office au-delà (taille du module de données)
local BIND_NAME = "ClipRecorderSample"
local FOLDER_NAME = "DebugClips"

type Deps = {
	player: Player,
	fpsCamera: any, -- FPSCamera (getCameraYaw, getCameraPitch)
	movement: any, -- MovementController (getVelocity)
}

local ClipRecorder = {}

local deps: Deps
local armedName: string?
local recording = false
local samples: { DemoClipRules.Sample } = {}
local elapsed = 0 -- secondes depuis le début de la prise
local nextAt = 0 -- instant du prochain échantillon à pas fixe
local previous: DemoClipRules.Sample? -- état de l'image précédente
local previousAt = 0
local status: TextLabel?

-- Cette méthode permet d'écrire une ligne préfixée lorsque l'enregistreur change d'état.
local function log(text: string)
	print("[ClipRecorder] " .. text)
end

-- Cette méthode permet d'afficher l'état de l'enregistreur en haut de l'écran lorsqu'il est armé ou enregistre.
local function showStatus(text: string?, live: boolean?)
	if not status then
		if not text then
			return
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "ClipRecorder"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		gui.Parent = deps.player:WaitForChild("PlayerGui")
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 70)
		label.Size = UDim2.fromOffset(420, 28)
		label.BackgroundColor3 = UITheme.Colors.Black
		label.BackgroundTransparency = 0.3
		label.FontFace = UITheme.Fonts.Display
		label.TextSize = 18
		label.Parent = gui
		status = label
	end
	local label = status :: TextLabel
	label.Visible = text ~= nil
	label.Text = text or ""
	label.TextColor3 = if live then UITheme.Colors.HitRed else UITheme.Colors.Bone
end

-- Cette méthode permet de lire l'état du joueur à l'image courante lorsque l'enregistreur tourne ; nil sans personnage.
local function readState(): DemoClipRules.Sample?
	local char = deps.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = workspace.CurrentCamera
	if not (root and camera) then
		return nil
	end
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local held = {}
	for _, action in DemoClipRules.KEY_ORDER do
		local down = false
		for _, name in (KeyBindings.KEYS :: any)[action] do
			if not typing and UserInputService:IsKeyDown((Enum.KeyCode :: any)[name]) then
				down = true
			end
		end
		held[action] = down
	end
	local velocity: Vector3 = deps.movement.getVelocity()
	local position = root.Position
	return {
		x = position.X,
		y = position.Y,
		z = position.Z,
		eye = camera.CFrame.Position.Y - position.Y,
		yaw = deps.fpsCamera.getCameraYaw(),
		pitch = deps.fpsCamera.getCameraPitch(),
		keys = DemoClipRules.keysMask(held),
		speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude,
	}
end

-- Cette méthode permet de ranger le clip encodé dans Player.DebugClips lorsque la prise s'arrête, pour l'extraction
-- par le MCP.
local function store(name: string, text: string)
	local folder = deps.player:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = deps.player
	end
	local value = folder:FindFirstChild(name) :: StringValue?
	if not value then
		local created = Instance.new("StringValue")
		created.Name = name
		created.Parent = folder
		value = created
	end
	(value :: StringValue).Value = text
end

-- Cette méthode permet d'arrêter la prise et de ranger le clip lorsque F7 est pressé ou que la durée maximale est atteinte.
local function stop()
	if not recording then
		return
	end
	recording = false
	RunService:UnbindFromRenderStep(BIND_NAME)
	local name = armedName or "clip"
	if #samples < 2 then
		log("STOP " .. name .. " : prise trop courte, rien de rangé")
	else
		local clip = { version = DemoClipRules.VERSION, hz = HZ, map = GameConfig.ACTIVE_MAP, samples = samples }
		local text = DemoClipRules.encode(clip)
		store(name, text)
		log(
			string.format(
				"STOP %s : %.1f s, %d échantillons, %d octets, rangé dans Player.%s.%s",
				name,
				DemoClipRules.duration(clip),
				#samples,
				#text,
				FOLDER_NAME,
				name
			)
		)
	end
	samples = {}
	showStatus(if armedName then string.format("CLIP %s PRÊT · F7 POUR ENREGISTRER", armedName) else nil)
end

-- Cette méthode permet de prendre les échantillons à pas fixe tombés entre l'image précédente et celle-ci lorsque
-- l'enregistreur tourne (après la caméra, sur le rendu).
local function step(dt: number)
	elapsed += dt
	local current = readState()
	if not current then
		return
	end
	local before = previous or current
	local beforeAt = if previous then previousAt else elapsed
	while nextAt <= elapsed do
		local span = elapsed - beforeAt
		local alpha = if span > 0 then math.clamp((nextAt - beforeAt) / span, 0, 1) else 1
		table.insert(samples, DemoClipRules.lerpSample(before, current, alpha))
		nextAt += 1 / HZ
	end
	previous, previousAt = current, elapsed
	showStatus(string.format("● REC %s  %.1f s · F7 POUR ARRÊTER", armedName or "clip", elapsed), true)
	if elapsed >= MAX_SECONDS then
		stop()
	end
end

-- Cette méthode permet de lancer une prise lorsque F7 est pressé avec l'enregistreur armé.
local function start()
	if recording or not armedName then
		return
	end
	recording = true
	samples = {}
	elapsed, nextAt, previous, previousAt = 0, 0, nil, 0
	log("REC " .. (armedName :: string))
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end

-- Cette méthode permet d'armer ou de désarmer l'enregistreur lorsque l'attribut DebugClipRecorder change.
local function onAttribute()
	local value = deps.player:GetAttribute(ATTRIBUTE)
	stop()
	armedName = if type(value) == "string" and value ~= "" then value else nil
	showStatus(if armedName then string.format("CLIP %s PRÊT · F7 POUR ENREGISTRER", armedName) else nil)
end

-- Cette méthode permet de brancher l'enregistreur lorsque le client démarre ; ne fait rien hors Studio.
function ClipRecorder.init(dependencies: Deps)
	if not RunService:IsStudio() then
		return
	end
	deps = dependencies
	deps.player:GetAttributeChangedSignal(ATTRIBUTE):Connect(onAttribute)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode ~= TOGGLE_KEY or not armedName then
			return
		end
		if recording then
			stop()
		else
			start()
		end
	end)
	onAttribute()
end

return ClipRecorder
