local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- RemoteEvent pour les dégâts melee (client → serveur)
local meleeEvent = Instance.new("RemoteEvent")
meleeEvent.Name = "MeleeDamage"
meleeEvent.Parent = ReplicatedStorage

meleeEvent.OnServerEvent:Connect(function(player, targetCharacter, damage)
	if typeof(targetCharacter) ~= "Instance" then return end
	if typeof(damage) ~= "number" then return end
	damage = math.clamp(damage, 0, 500)

	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return end

	-- Vérifier que le joueur n'est pas en train de se tirer dessus
	if player.Character == targetCharacter then return end

	humanoid:TakeDamage(damage)
end)
