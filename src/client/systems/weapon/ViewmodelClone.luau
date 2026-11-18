-- Viewmodel hors du jeu : copie du modèle d'une arme (ReplicatedStorage.ViewModels, habillée de son skin) posée devant
-- une caméra scriptée, pistes chargées, pour les scènes qui montrent un tir en 1re personne sans personnage du joueur :
-- clip de la partie (HighlightPlayer, #499) et démonstration des effets de tir (EffectStage, #575).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponSkins = require(ReplicatedStorage.Shared.WeaponSkins)
local AnimationSoundSystem = require(script.Parent.AnimationSoundSystem)

local ViewmodelClone = {}

-- Viewmodel préparé : modèle, fiche WeaponConfig de l'arme, décalage devant la caméra (attribut ViewmodelOffset du
-- Tool), pièces (cachées par leur modificateur de transparence) et pistes chargées par nom d'Animation
export type Held = {
	model: Model,
	weapon: string,
	offset: CFrame,
	parts: { BasePart },
	tracks: { [string]: AnimationTrack },
}

-- Cette méthode permet de trouver le Tool d'une arme (ReplicatedStorage.Tools) lorsqu'une scène prépare son viewmodel.
function ViewmodelClone.tool(toolName: string?): Tool?
	local tools = ReplicatedStorage:FindFirstChild("Tools")
	local tool = tools and toolName and tools:FindFirstChild(toolName)
	return if tool and tool:IsA("Tool") then tool else nil
end

-- Cette méthode permet de montrer ou cacher un viewmodel lorsque l'arme sort, est rangée ou que le plan change (caché
-- par le modificateur de transparence, comme ViewmodelSystem : les pistes restent chargées).
function ViewmodelClone.setVisible(held: Held, visible: boolean)
	local modifier = if visible then 0 else 1
	for _, part in held.parts do
		part.LocalTransparencyModifier = modifier
	end
end

-- Cette méthode permet de préparer, caché devant `camera`, le viewmodel de l'arme du Tool `toolName` habillé du skin
-- `skinId` (nil : d'origine) lorsqu'une scène démarre : clone sans ombre, rangé sous la caméra, pistes chargées et
-- boucle Idle prête ; nil sans Tool ou sans modèle.
function ViewmodelClone.build(camera: Camera, toolName: string?, skinId: string?): Held?
	local tool = ViewmodelClone.tool(toolName)
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
	if skinId then
		WeaponSkins.apply(model, viewmodelName, skinId)
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
	ViewmodelClone.setVisible(held, false)
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

return ViewmodelClone
