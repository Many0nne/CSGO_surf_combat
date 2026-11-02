return function(T, Loader)
	-- Cette méthode permet de construire un personnage minimal (root + humanoid) lorsqu'un test a besoin d'une cible ;
	-- facing oriente le root (Lune ne déduit pas Position de CFrame : les deux sont posés).
	local function makeCharacter(position: Vector3, health: number?, facing: Vector3?)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = position
		root.CFrame = if facing then CFrame.lookAt(position, position + facing) else CFrame.new(position)
		root.Parent = model
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = health or 100
		humanoid.Parent = model
		return model
	end

	-- Cette méthode permet de mettre un outil en main d'un joueur lorsqu'un test attaque avec une arme donnée.
	local function equip(player, toolName: string, weaponName: string?)
		local tool = Instance.new("Tool")
		tool.Name = toolName
		if weaponName then
			tool:SetAttribute("WeaponName", weaponName)
		end
		tool.Parent = player.Character
		return tool
	end

	-- Cette méthode permet de créer un Validator avec un service Players simulé lorsque les tests
	-- ont besoin d'associer des personnages à des joueurs ; makePlayer peut lui donner une arme en main.
	local function setup()
		local owners = {}
		local Players = {
			GetPlayerFromCharacter = function(_, character)
				return owners[character]
			end,
		}
		local Validator = Loader.new({ Players = Players }):require("src/server/Validator")
		local function makePlayer(position: Vector3, weapon: string?, health: number?, facing: Vector3?)
			local player = { Character = makeCharacter(position, health, facing) }
			owners[player.Character] = player
			if weapon then
				equip(player, weapon)
			end
			return player
		end
		return Validator, makePlayer
	end

	T.describe("Validator : cibles", function()
		T.it("accepte un tir valide entre deux joueurs", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(100, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, 0), 115)
		end)

		T.it("refuse de se toucher soi-même", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			T.expectEqual(Validator.authorizeHitscan(a, a.Character, 0), nil)
		end)

		T.it("refuse un tir au-delà de la portée max", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(251, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, 0), nil)
		end)

		T.it("refuse un coup de melee au-delà de 10 studs", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "M9Bayonet")
			T.expectEqual(Validator.authorizeMelee(a, makePlayer(Vector3.new(11, 0, 0)).Character, "primary", 0), nil)
			T.expectEqual(Validator.authorizeMelee(a, makePlayer(Vector3.new(9, 0, 0)).Character, "primary", 0), 50)
		end)

		T.it("refuse une cible déjà morte", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(5, 0, 0), nil, 0)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, 0), nil)
		end)

		T.it("refuse un modèle qui n'est ni joueur ni cible de playtest, accepte la cible", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			local npc = makeCharacter(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, npc, 0), nil, "modèle non tagué accepté")
			npc:SetAttribute("IsBot", true)
			T.expectEqual(Validator.authorizeHitscan(a, npc, 0), nil, "ancien attribut IsBot accepté")
			npc:SetAttribute(Validator.DEBUG_TARGET_ATTRIBUTE, true)
			T.expectEqual(Validator.authorizeHitscan(a, npc, 0), 115, "cible de playtest refusée")
		end)

		T.it("refuse une cible qui n'est pas une Instance", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			T.expectEqual(Validator.authorizeHitscan(a, {} :: any, 0), nil)
		end)

		T.it("refuse si l'attaquant n'a pas de personnage", function()
			local Validator, makePlayer = setup()
			local b = makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeHitscan({ Character = nil } :: any, b.Character, 0), nil)
		end)
	end)

	T.describe("Validator : arme en main", function()
		T.it("refuse une attaque sans arme en main", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero), makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, 0), nil)
		end)

		T.it("refuse un coup de melee avec une arme à distance, et un tir avec un couteau", function()
			local Validator, makePlayer = setup()
			local b = makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeMelee(makePlayer(Vector3.zero, "AWP"), b.Character, "primary", 0), nil)
			T.expectEqual(Validator.authorizeHitscan(makePlayer(Vector3.zero, "M9Bayonet"), b.Character, 0), nil)
		end)

		T.it("refuse un outil sans entrée dans WeaponConfig", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "Inconnu"), makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, 0), nil)
		end)

		T.it("lit l'arme dans l'attribut WeaponName, sinon le nom de l'outil", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero), makePlayer(Vector3.new(5, 0, 0))
			equip(a, "Couteau", "M9Bayonet")
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50)
		end)
	end)

	T.describe("Validator : dégâts de mêlée", function()
		T.it("calcule les dégâts depuis WeaponConfig selon le clic", function()
			local Validator, makePlayer = setup()
			local b = makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(
				Validator.authorizeMelee(makePlayer(Vector3.zero, "M9Bayonet"), b.Character, "primary", 0),
				50
			)
			T.expectEqual(
				Validator.authorizeMelee(makePlayer(Vector3.zero, "M9Bayonet"), b.Character, "secondary", 0),
				65
			)
		end)

		T.it("refuse un type d'attaque inconnu, dont d'anciens dégâts envoyés par le client", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "M9Bayonet"), makePlayer(Vector3.new(5, 0, 0))
			for _, attackKind in { "tertiary", 500, true, {} :: any } do
				T.expectEqual(Validator.authorizeMelee(a, b.Character, attackKind, 0), nil, tostring(attackKind))
			end
			T.expectEqual(Validator.authorizeMelee(a, b.Character, nil :: any, 0), nil, "nil accepté")
		end)

		T.it("multiplie les dégâts dans le dos de la cible, selon les positions du serveur", function()
			local Validator, makePlayer = setup()
			-- La cible regarde vers +X : l'attaquant à l'origine est derrière elle.
			local behind = makePlayer(Vector3.new(5, 0, 0), nil, nil, Vector3.new(1, 0, 0))
			T.expectEqual(
				Validator.authorizeMelee(makePlayer(Vector3.zero, "M9Bayonet"), behind.Character, "primary", 0),
				100
			)
			T.expectEqual(
				Validator.authorizeMelee(makePlayer(Vector3.zero, "M9Bayonet"), behind.Character, "secondary", 0),
				130
			)
		end)

		T.it("ne multiplie pas les dégâts de face", function()
			local Validator, makePlayer = setup()
			local facing = makePlayer(Vector3.new(5, 0, 0), nil, nil, Vector3.new(-1, 0, 0))
			T.expectEqual(
				Validator.authorizeMelee(makePlayer(Vector3.zero, "M9Bayonet"), facing.Character, "primary", 0),
				50
			)
		end)
	end)

	T.describe("Validator : cadence", function()
		T.it("refuse un coup avant la fin de la cadence, tolérance de latence comprise", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "M9Bayonet"), makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10), 50)
			T.expectEqual(
				Validator.authorizeMelee(a, b.Character, "primary", 10.2),
				nil,
				"0,2 s après un slash de 0,4 s"
			)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10.3), 50, "tolérance non appliquée")
		end)

		T.it("partage la cadence entre les deux clics et applique celle de l'attaque précédente", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "M9Bayonet"), makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10), 50)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "secondary", 10.2), nil, "estoc pendant un slash")
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "secondary", 10.4), 65, "estoc après un slash")
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10.9), nil, "slash pendant l'estoc (1 s)")
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 11.4), 50, "slash après l'estoc")
		end)

		T.it("ne relance pas la cadence sur un coup refusé", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "M9Bayonet"), makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10), 50)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10.2), nil)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10.3), 50)
		end)

		T.it("ne démarre pas la cadence sur une cible invalide", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "M9Bayonet")
			T.expectEqual(Validator.authorizeMelee(a, makePlayer(Vector3.new(50, 0, 0)).Character, "primary", 10), nil)
			T.expectEqual(Validator.authorizeMelee(a, makePlayer(Vector3.new(5, 0, 0)).Character, "primary", 10), 50)
		end)

		T.it("applique la cadence de l'arme aux tirs", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, 10), 115)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, 11), nil, "1 s après un tir (cadence 1,46 s)")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, 11.4), 115, "tolérance non appliquée")
		end)

		T.it("suit la cadence par joueur et par arme, comme le client", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "M9Bayonet")
			local other = makePlayer(Vector3.zero, "M9Bayonet")
			local b = makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "secondary", 10), 65)
			T.expectEqual(Validator.authorizeMelee(other, b.Character, "primary", 10), 50, "autre joueur bloqué")
			a.Character:FindFirstChildOfClass("Tool"):Destroy()
			equip(a, "AWP")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, 10.1), 115, "autre arme bloquée")
		end)

		T.it("oublie les cadences d'un joueur à sa demande", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "M9Bayonet"), makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "secondary", 10), 65)
			Validator.forgetPlayer(a)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10.1), 50)
		end)
	end)

	T.describe("Validator : qualification d'une touche", function()
		T.it("qualifie une touche selon les PV avant et après les dégâts", function()
			local Validator = setup()
			T.expectEqual(Validator.hitOutcome(100, 50), "hit")
			T.expectEqual(Validator.hitOutcome(100, 0), "kill")
			T.expectEqual(Validator.hitOutcome(50, -15), "kill")
		end)

		T.it("ne confirme rien si les PV n'ont pas baissé (ForceField)", function()
			local Validator = setup()
			T.expectEqual(Validator.hitOutcome(100, 100), nil)
		end)
	end)
end
