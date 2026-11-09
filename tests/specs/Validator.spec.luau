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

	-- Cette méthode permet de lire la partie touchée par défaut (zone ×1) lorsqu'un test ne porte pas sur les zones.
	local function rootOf(character)
		return character:FindFirstChild("HumanoidRootPart")
	end

	-- Cette méthode permet d'ajouter une partie sous un parent lorsqu'un test tire sur une zone donnée.
	local function addPart(parent, name: string)
		local part = Instance.new("Part")
		part.Name = name
		part.Parent = parent
		return part
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
	-- Le Validator reçoit des participants : l'enveloppe convertit le tireur comme le fait init.server (fromPlayer),
	-- et makeBot inscrit un bot (participant sans Player) ; un bot s'y passe tel quel.
	local function setup()
		local owners = {}
		local Players = {
			GetPlayerFromCharacter = function(_, character)
				return owners[character]
			end,
		}
		local loader = Loader.new({ Players = Players })
		local Real = loader:require("src/server/Validator")
		local Participants = loader:require("src/server/Participants")
		local nextUserId = 0
		local function participantOf(attacker)
			return if attacker.isBot then attacker else Participants.fromPlayer(attacker)
		end
		local Validator = {
			DEBUG_TARGET_ATTRIBUTE = Real.DEBUG_TARGET_ATTRIBUTE,
			hitOutcome = Real.hitOutcome,
			authorizeHitscan = function(attacker, ...)
				return Real.authorizeHitscan(participantOf(attacker), ...)
			end,
			authorizeMelee = function(attacker, ...)
				return Real.authorizeMelee(participantOf(attacker), ...)
			end,
			forget = function(attacker)
				Real.forget(participantOf(attacker))
			end,
		}
		local function makePlayer(position: Vector3, weapon: string?, health: number?, facing: Vector3?)
			nextUserId += 1
			local player = {
				UserId = nextUserId,
				Name = "Joueur" .. nextUserId,
				Character = makeCharacter(position, health, facing),
			}
			owners[player.Character] = player
			-- inscrit comme à son arrivée en jeu (init.server : setupPlayer)
			Participants.fromPlayer(player :: any)
			if weapon then
				equip(player, weapon)
			end
			return player
		end
		local function makeBot(position: Vector3, weapon: string?)
			local bot = Participants.addBot("Marcel")
			Participants.setCharacter(bot, makeCharacter(position))
			-- equip lit .Character : même forme qu'un faux joueur
			bot.Character = bot.character
			if weapon then
				equip(bot, weapon)
			end
			return bot
		end
		return Validator, makePlayer, makeBot
	end

	T.describe("Validator : bots (#137)", function()
		T.it("accepte un tir d'un joueur sur un bot", function()
			local Validator, makePlayer, makeBot = setup()
			local a, bot = makePlayer(Vector3.zero, "AWP"), makeBot(Vector3.new(100, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, bot.character, rootOf(bot.character), 0), 115)
		end)

		T.it("accepte un tir d'un bot sur un joueur", function()
			local Validator, makePlayer, makeBot = setup()
			local bot, b = makeBot(Vector3.zero, "AWP"), makePlayer(Vector3.new(100, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(bot, b.Character, rootOf(b.Character), 0), 115)
		end)

		T.it("refuse qu'un bot se touche lui-même", function()
			local Validator, _, makeBot = setup()
			local bot = makeBot(Vector3.zero, "AWP")
			T.expectEqual(Validator.authorizeHitscan(bot, bot.character, rootOf(bot.character), 0), nil)
		end)

		T.it("refuse un personnage sans participant", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			local orphan = makeCharacter(Vector3.new(50, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, orphan, rootOf(orphan), 0), nil)
		end)
	end)

	T.describe("Validator : cibles", function()
		T.it("accepte un tir valide entre deux joueurs", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(100, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0), 115)
		end)

		T.it("refuse de se toucher soi-même", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			T.expectEqual(Validator.authorizeHitscan(a, a.Character, rootOf(a.Character), 0), nil)
		end)

		T.it("refuse un tir au-delà de la portée max", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(251, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0), nil)
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
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0), nil)
		end)

		T.it("refuse un modèle qui n'est ni joueur ni cible de playtest, accepte la cible", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			local npc = makeCharacter(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, npc, rootOf(npc), 0), nil, "modèle non tagué accepté")
			npc:SetAttribute("IsBot", true)
			T.expectEqual(Validator.authorizeHitscan(a, npc, rootOf(npc), 0), nil, "ancien attribut IsBot accepté")
			npc:SetAttribute(Validator.DEBUG_TARGET_ATTRIBUTE, true)
			T.expectEqual(Validator.authorizeHitscan(a, npc, rootOf(npc), 0), 115, "cible de playtest refusée")
		end)

		T.it("refuse une cible qui n'est pas une Instance", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			T.expectEqual(Validator.authorizeHitscan(a, {} :: any, nil :: any, 0), nil)
		end)

		T.it("refuse si l'attaquant n'a pas de personnage", function()
			local Validator, makePlayer = setup()
			local b = makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(
				Validator.authorizeHitscan(
					{ UserId = 99, Name = "SansPerso" } :: any,
					b.Character,
					rootOf(b.Character),
					0
				),
				nil
			)
		end)
	end)

	T.describe("Validator : arme en main", function()
		T.it("refuse une attaque sans arme en main", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero), makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0), nil)
		end)

		T.it("refuse un coup de melee avec une arme à distance, et un tir avec un couteau", function()
			local Validator, makePlayer = setup()
			local b = makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeMelee(makePlayer(Vector3.zero, "AWP"), b.Character, "primary", 0), nil)
			T.expectEqual(
				Validator.authorizeHitscan(makePlayer(Vector3.zero, "M9Bayonet"), b.Character, rootOf(b.Character), 0),
				nil
			)
		end)

		T.it("refuse un outil sans entrée dans WeaponConfig", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "Inconnu"), makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0), nil)
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
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 10), 115)
			T.expectEqual(
				Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 11),
				nil,
				"1 s après un tir (cadence 1,46 s)"
			)
			T.expectEqual(
				Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 11.4),
				115,
				"tolérance non appliquée"
			)
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
			T.expectEqual(
				Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 10.1),
				115,
				"autre arme bloquée"
			)
		end)

		T.it("oublie les cadences d'un joueur à sa demande", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "M9Bayonet"), makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "secondary", 10), 65)
			Validator.forget(a)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10.1), 50)
		end)
	end)

	T.describe("Validator : zones du corps", function()
		-- Cette méthode permet de préparer un tireur à l'AWP et sa cible lorsqu'un test tire sur une zone.
		local function setupShot()
			local Validator, makePlayer = setup()
			return Validator, makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(20, 0, 0))
		end

		T.it("applique le multiplicateur de la zone et signale le tir à la tête", function()
			for partName, expected in { Head = 460, UpperTorso = 115, LowerTorso = 115, LeftHand = 115, RightFoot = 86 } do
				local Validator, a, b = setupShot()
				local damage, isHeadshot = Validator.authorizeHitscan(a, b.Character, addPart(b.Character, partName), 0)
				T.expectEqual(damage, expected, partName)
				T.expectEqual(isHeadshot, partName == "Head", partName)
			end
		end)

		T.it("compte une partie inconnue à ×1", function()
			local Validator, a, b = setupShot()
			local damage, isHeadshot = Validator.authorizeHitscan(a, b.Character, addPart(b.Character, "Inconnue"), 0)
			T.expectEqual(damage, 115)
			T.expectEqual(isHeadshot, false)
		end)

		T.it("n'accorde pas la tête à une pièce d'accessoire nommée Head", function()
			local Validator, a, b = setupShot()
			local accessory = Instance.new("Accessory")
			accessory.Parent = b.Character
			local damage, isHeadshot = Validator.authorizeHitscan(a, b.Character, addPart(accessory, "Head"), 0)
			T.expectEqual(damage, 115)
			T.expectEqual(isHeadshot, false)
		end)

		T.it("refuse une partie hors de la cible sans démarrer la cadence", function()
			local Validator, a, b = setupShot()
			local elsewhere = addPart(Instance.new("Model"), "Head")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, elsewhere, 0), nil, "partie d'un autre modèle")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(a.Character), 0), nil, "partie du tireur")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, "Head" :: any, 0), nil, "chaîne")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, nil :: any, 0), nil, "nil")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0), 115, "cadence démarrée")
		end)

		T.it("ne change pas les dégâts du couteau selon la zone", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "M9Bayonet")
			local b = makePlayer(Vector3.new(5, 0, 0), nil, nil, Vector3.new(-1, 0, 0))
			addPart(b.Character, "Head")
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50)
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
