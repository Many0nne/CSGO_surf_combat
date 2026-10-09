return function(T, Loader)
	-- Cette méthode permet de construire un personnage minimal (root + humanoid) lorsqu'un test a besoin d'une cible.
	local function makeCharacter(position: Vector3, health: number?)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = position
		root.Parent = model
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = health or 100
		humanoid.Parent = model
		return model
	end

	-- Cette méthode permet de créer un Validator avec un service Players simulé lorsque les tests
	-- ont besoin d'associer des personnages à des joueurs.
	local function setup()
		local owners = {}
		local Players = {
			GetPlayerFromCharacter = function(_, character)
				return owners[character]
			end,
		}
		local Validator = Loader.new({ Players = Players }):require("src/server/Validator")
		local function makePlayer(position: Vector3, health: number?)
			local player = { Character = makeCharacter(position, health) }
			owners[player.Character] = player
			return player
		end
		return Validator, makePlayer
	end

	T.describe("Validator", function()
		T.it("accepte un hitscan valide entre deux joueurs", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero), makePlayer(Vector3.new(100, 0, 0))
			T.expect(Validator.validateHitscan(a, b.Character, 30))
		end)

		T.it("refuse de se toucher soi-même", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero)
			T.expect(not Validator.validateHitscan(a, a.Character, 30))
		end)

		T.it("refuse des dégâts nuls, négatifs, excessifs ou non numériques", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero), makePlayer(Vector3.new(5, 0, 0))
			for _, damage in { 0, -10, 1001, "30" :: any } do
				T.expect(not Validator.validateHitscan(a, b.Character, damage), "accepté : " .. tostring(damage))
			end
			T.expect(not Validator.validateMelee(a, b.Character, 501), "melee > 500 accepté")
		end)

		T.it("refuse un hitscan au-delà de la portée max", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero), makePlayer(Vector3.new(251, 0, 0))
			T.expect(not Validator.validateHitscan(a, b.Character, 30))
		end)

		T.it("refuse un coup de melee au-delà de 10 studs", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero)
			T.expect(Validator.validateMelee(a, makePlayer(Vector3.new(9, 0, 0)).Character, 50))
			T.expect(not Validator.validateMelee(a, makePlayer(Vector3.new(11, 0, 0)).Character, 50))
		end)

		T.it("refuse une cible déjà morte", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero), makePlayer(Vector3.new(5, 0, 0), 0)
			T.expect(not Validator.validateHitscan(a, b.Character, 30))
		end)

		T.it("refuse un modèle qui n'est ni joueur ni bot, accepte un bot", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero)
			local npc = makeCharacter(Vector3.new(5, 0, 0))
			T.expect(not Validator.validateHitscan(a, npc, 30), "PNJ non tagué accepté")
			npc:SetAttribute("IsBot", true)
			T.expect(Validator.validateHitscan(a, npc, 30), "bot refusé")
		end)

		T.it("refuse une cible qui n'est pas une Instance", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero)
			T.expect(not Validator.validateHitscan(a, {} :: any, 30))
		end)

		T.it("refuse si l'attaquant n'a pas de personnage", function()
			local Validator, makePlayer = setup()
			local b = makePlayer(Vector3.new(5, 0, 0))
			T.expect(not Validator.validateHitscan({ Character = nil } :: any, b.Character, 30))
		end)
	end)
end
