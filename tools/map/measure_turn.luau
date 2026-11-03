-- measure_turn.luau
-- Mesure la perte de vitesse dans un virage de l'Arène : un surfeur sans input entre dans le virage +Z depuis la
-- ligne droite x = +RING_W, et l'on compare son énergie (½v² + g·h) à l'entrée et à la sortie. Sans frottement,
-- elle doit rester constante : la vitesse perdue en montant la dune revient en redescendant.
-- À exécuter DANS Studio, mode Edit, map Arène chargée, plugin Rojo connecté au worktree (le code de mouvement mesuré
-- est celui que Rojo a synchronisé) : `lune run tools/map/serve.luau`, puis (MCP `execute_luau`, contexte Edit)
--   return loadstring(game:GetService("HttpService"):GetAsync("http://localhost:34992/measure_turn.luau"))()
-- Reproduit la branche aérienne de MovementController (demi-pas de gravité, WallSlide.resolve, commitMove).

local RING_W, RING_L, BANK_H, BANK_SLOPE = 120, 170, 55, 55 -- mêmes valeurs que build_arena.luau
local SUN_DIR = Vector3.new(-0.9168, 0, -0.3987).Unit
local G = require(game:GetService("ReplicatedStorage").Shared.MovementConfig).GRAVITY
local source = game:GetService("StarterPlayer").StarterPlayerScripts.Client.systems.movement.WallSlide
local WS = require(source:Clone()) -- copie fraîche : la sonde de pénétration du module est recréée
local base = CFrame.lookAt(Vector3.zero, SUN_DIR)
local hull = { rootToTop = 2.4, rootToBottom = 2.4, radius = 1.0, centerOffset = 0 }
local TAN = math.tan(math.rad(BANK_SLOPE))

-- Cette méthode permet de lancer un surfeur à `speed` studs/s sur la ligne droite, 30 studs avant le virage,
-- et de renvoyer une ligne de mesure (angle parcouru dans le virage, variation d'énergie, vitesses).
local function run(speed: number): string
	local startX = RING_W - 12
	local h = (startX - (RING_W - BANK_H / TAN)) * TAN
	local hrp = { Position = base * Vector3.new(startX, h + 7, RING_L - 30) }
	local vel = base:VectorToWorldSpace(Vector3.new(0, -5, speed))
	local safe, surf = hrp.Position, nil
	local dt = 1 / 60
	local first, last
	for _ = 1, 600 do
		vel += Vector3.new(0, G * 0.5 * dt, 0)
		local nv, mv, hn, stepped = WS.resolve(hrp :: any, vel, dt, surf, hull)
		vel = nv
		local cand = hrp.Position + mv
		if stepped then
			cand = WS.ejectUp(cand, safe, hull)
		else
			cand, vel = WS.commitMove(safe, cand, vel, hull)
		end
		hrp.Position = cand
		if not WS.penInfo(cand, hull) then
			safe = cand
		end
		vel += Vector3.new(0, G * 0.5 * dt, 0)
		surf = if hn and hn.Y >= 0.1 and hn.Y < 0.7 then hn else nil
		local lp = base:PointToObjectSpace(hrp.Position)
		if surf and lp.Z > RING_L then
			local sample = {
				E = 0.5 * vel.Magnitude ^ 2 - G * hrp.Position.Y,
				v = vel.Magnitude,
				ang = math.deg(math.atan2(lp.Z - RING_L, lp.X)),
			}
			first = first or sample
			last = sample
		end
		if lp.Y < 3 or (lp.Z < RING_L and lp.X < 0) then
			break
		end
	end
	if not first then
		return string.format("v0=%d : jamais en surf dans le virage", speed)
	end
	return string.format(
		"v0=%d : virage %.0f° -> %.0f°, énergie %+.1f %%, vitesse %.0f -> %.0f",
		speed,
		first.ang,
		last.ang,
		100 * (last.E - first.E) / first.E,
		first.v,
		last.v
	)
end

local dummy = Instance.new("Model")
WS.init(dummy)
local lines = {}
for _, speed in { 140, 150, 165 } do
	table.insert(lines, run(speed))
end
dummy:Destroy()
local probe = workspace:FindFirstChild("PenProbe") -- posée par WS.init, la copie du module ne sert plus
if probe then
	probe:Destroy()
end
return table.concat(lines, "\n")
