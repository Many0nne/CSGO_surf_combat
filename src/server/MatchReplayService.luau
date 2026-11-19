-- Rejeu d'un enregistrement de partie (#582), côté serveur, dans Studio seulement : les enregistrements extraits par
-- tools/matchrec/extract.luau sont dans recordings/<Nom>/ (un .txt par morceau), synchronisés par Rojo dans
-- ServerStorage.MatchRecordings.<Nom>. Quand l'attribut joueur `MatchReplay` (contexte Server) nomme un
-- enregistrement, ses morceaux et le rig des personnages sont copiés dans ReplicatedStorage.MatchReplayData, puis
-- l'attribut `MatchReplayReady` reprend le nom (vide : introuvable) ; le client (debug/MatchReplay) rejoue la partie.
-- Hors de Studio, le dossier des enregistrements est retiré au démarrage (rien n'est lu ni envoyé).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CharacterAppearance = require(ReplicatedStorage.Shared.CharacterAppearance)

local SOURCE_NAME = "MatchRecordings"
local DATA_NAME = "MatchReplayData"
local ATTRIBUTE = "MatchReplay"
local READY_ATTRIBUTE = "MatchReplayReady"

local MatchReplayService = {}

-- Cette méthode permet de lister les enregistrements disponibles lorsqu'un nom demandé est introuvable.
local function available(source: Instance?): string
	local names = {}
	if source then
		for _, child in source:GetChildren() do
			table.insert(names, child.Name)
		end
	end
	table.sort(names)
	return if #names > 0 then table.concat(names, ", ") else "aucun (recordings/ vide)"
end

-- Cette méthode permet de publier un enregistrement pour le client lorsque l'attribut MatchReplay du joueur change :
-- morceaux et rig copiés dans ReplicatedStorage, puis MatchReplayReady posé (vide si introuvable ; nil à l'arrêt).
local function onAttribute(player: Player)
	local name = player:GetAttribute(ATTRIBUTE)
	local previous = ReplicatedStorage:FindFirstChild(DATA_NAME)
	if type(name) ~= "string" or name == "" then
		if previous then
			previous:Destroy()
		end
		player:SetAttribute(READY_ATTRIBUTE, nil)
		return
	end
	local source = ServerStorage:FindFirstChild(SOURCE_NAME)
	local recording = source and source:FindFirstChild(name)
	if not recording then
		warn(string.format("[MatchReplay] enregistrement %q introuvable ; disponibles : %s", name, available(source)))
		player:SetAttribute(READY_ATTRIBUTE, "")
		return
	end
	if previous then
		previous:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = DATA_NAME
	local chunks = recording:Clone()
	chunks.Name = "Chunks"
	chunks.Parent = folder
	local template = CharacterAppearance.getTemplate()
	if template then
		local wasArchivable = template.Archivable
		template.Archivable = true
		local rig = template:Clone()
		template.Archivable = wasArchivable
		rig.Name = "Rig"
		rig.Parent = folder
	end
	folder:SetAttribute("Name", name)
	folder.Parent = ReplicatedStorage
	player:SetAttribute(READY_ATTRIBUTE, name)
	print(string.format("[MatchReplay] %s publié (%d morceau(x))", name, #chunks:GetChildren()))
end

-- Cette méthode permet de brancher le rejeu lorsque le serveur démarre : dans Studio, écoute de l'attribut de chaque
-- joueur ; ailleurs, retrait du dossier des enregistrements.
function MatchReplayService.init()
	if not RunService:IsStudio() then
		local source = ServerStorage:FindFirstChild(SOURCE_NAME)
		if source then
			source:Destroy()
		end
		return
	end
	-- Cette méthode permet de suivre l'attribut d'un joueur lorsqu'il arrive.
	local function watch(player: Player)
		player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
			onAttribute(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return MatchReplayService
