-- Mort par chute : la map est une île au-dessus du vide. Le mouvement est fait par le client et le serveur ne voit
-- pas la position du personnage (racine ancrée) : c'est le client qui signale qu'il est passé sous
-- Maps.Map.KillHeight (remote FellOut), et le serveur le tue (mort sans tueur, comptée via Humanoid.Died).
-- Un client ne peut ainsi tuer que lui-même.

local KillZone = {}

-- Cette méthode permet de tuer le joueur qui signale sa chute lorsqu'il est encore vivant ;
-- Health = 0 passe outre la protection d'apparition (ForceField), voulu : on ne survit pas au vide.
function KillZone.init(fellOutRemote: RemoteEvent)
	fellOutRemote.OnServerEvent:Connect(function(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Health = 0
		end
	end)
end

return KillZone
