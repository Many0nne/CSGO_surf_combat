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

	-- Cette méthode permet d'ajouter une partie sous un parent lorsqu'un test tire sur une zone donnée ; elle est posée
	-- sur la racine du personnage qui la contient (Lune n'a pas de Position par défaut), décalée de offset.
	local function addPart(parent, name: string, offset: Vector3?)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(1, 1, 1)
		local holder = parent
		local root = holder:FindFirstChild("HumanoidRootPart")
			or (holder.Parent and holder.Parent:FindFirstChild("HumanoidRootPart"))
		part.Position = (if root then root.Position else Vector3.zero) + (offset or Vector3.zero)
		part.Parent = parent
		return part
	end

	-- Hauteur de la caméra au-dessus de la racine (CameraConfig.CAM_HEIGHT_STAND) : origine d'un tir honnête.
	local EYE = Vector3.new(0, 2.5, 0)

	-- Arrivée d'un outil vue par le serveur (#175), branchée par setup : comme trackWeapon3P dans init.server.
	local onEquip: ((any, any, number?) -> ())? = nil
	-- Instant d'equip par défaut, loin dans le passé : un test qui ne porte pas sur l'equip tire avec une arme sortie.
	local LONG_AGO = -1000

	-- Cette méthode permet de mettre un outil en main d'un joueur lorsqu'un test attaque avec une arme donnée ; at est
	-- l'instant où le serveur voit l'outil arriver (LONG_AGO par défaut).
	local function equip(player, toolName: string, weaponName: string?, at: number?)
		local tool = Instance.new("Tool")
		tool.Name = toolName
		if weaponName then
			tool:SetAttribute("WeaponName", weaponName)
		end
		tool.Parent = player.Character
		if onEquip then
			onEquip(player, tool, at)
		end
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
		local ShotRules = loader:require("src/server/ShotRules")
		-- Monde simulé de la validation des tirs (#174) : horloge serveur, historiques (fonction t -> position par
		-- personnage, sinon pas d'historique), obstacle de la map (booléen, ou fonction (from, delta) -> booléen),
		-- violations reçues.
		local world = { now = 100, histories = {}, obstructed = false :: any, reports = {} }
		Real.setShotWorld({
			serverNow = function()
				return world.now
			end,
			positionAt = function(char, t)
				local history = world.histories[char]
				return if history then history(math.clamp(t, world.now - 0.4, world.now)) else nil
			end,
			isObstructed = function(from, delta)
				if type(world.obstructed) == "function" then
					return world.obstructed(from, delta)
				end
				return world.obstructed
			end,
			report = function(attacker, check, severity, detail, category)
				table.insert(world.reports, {
					attacker = attacker,
					check = check,
					severity = severity,
					detail = detail,
					category = category or "Hitscan",
				})
			end,
		})
		local nextUserId = 0
		local function participantOf(attacker)
			return if attacker.isBot then attacker else Participants.fromPlayer(attacker)
		end
		onEquip = function(attacker, tool, at)
			Real.noteEquip(participantOf(attacker), tool, at or LONG_AGO)
		end
		-- Cette méthode permet de construire le tir qu'enverrait notre client lorsqu'un test ne porte pas sur sa
		-- validation : depuis l'œil du tireur, droit sur la partie touchée, à l'instant présent.
		local function honestShot(attacker, hitPart)
			local char = attacker.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root or typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") then
				return nil
			end
			local origin = root.Position + EYE
			return {
				origin = origin,
				direction = (hitPart.Position - origin).Unit,
				hitPos = hitPart.Position,
				shotTime = world.now,
			}
		end
		local Validator = {
			DEBUG_TARGET_ATTRIBUTE = Real.DEBUG_TARGET_ATTRIBUTE,
			MAX_HITSCAN_RANGE = Real.MAX_HITSCAN_RANGE,
			hitOutcome = Real.hitOutcome,
			-- Sans shot, un joueur tire comme notre client ; `false` envoie un tir sans shot (client modifié)
			authorizeHitscan = function(attacker, targetCharacter, hitPart, now, shot)
				if shot == nil and not attacker.isBot then
					shot = honestShot(attacker, hitPart)
				elseif shot == false then
					shot = nil
				end
				return Real.authorizeHitscan(participantOf(attacker), targetCharacter, hitPart, now, shot)
			end,
			authorizeMelee = function(attacker, ...)
				return Real.authorizeMelee(participantOf(attacker), ...)
			end,
			forget = function(attacker)
				Real.forget(participantOf(attacker))
			end,
			noteReload = function(attacker, now)
				Real.noteReload(participantOf(attacker), now)
			end,
			noteUnequip = function(attacker, tool, now)
				Real.noteUnequip(participantOf(attacker), tool, now)
			end,
			noteEquip = function(attacker, tool, now)
				Real.noteEquip(participantOf(attacker), tool, now)
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
		return Validator, makePlayer, makeBot, world, ShotRules
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
			local a = makePlayer(Vector3.zero, "AWP")
			local b = makePlayer(Vector3.new(Validator.MAX_HITSCAN_RANGE + 1, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0), nil)
		end)

		T.it("accepte un tir lointain dans la portée du client (plus de borne à 250 studs)", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(1500, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0), 115)
			T.expectEqual(#world.reports, 0, "violation pour un tir légitime")
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
			-- Comme à la réapparition : l'oubli précède l'arrivée des armes neuves (init.server)
			a.Character:FindFirstChildOfClass("Tool"):Destroy()
			equip(a, "M9Bayonet")
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10.1), 50)
		end)
	end)

	T.describe("Validator : durée d'equip (#175)", function()
		T.it("refuse un tir pendant l'equip, l'accepte à EquipTime moins la tolérance", function()
			local Validator, makePlayer, _, world, ShotRules = setup()
			local a = makePlayer(Vector3.zero)
			local b = makePlayer(Vector3.new(50, 0, 0))
			equip(a, "AWP", nil, 10)
			local limit = 10 + 1.58 - ShotRules.EQUIP_TOLERANCE
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 10.5), nil, "tir à 0,5 s")
			T.expectEqual(#world.reports, 1, "refus journalisé")
			T.expectEqual(world.reports[1].check, "equip")
			T.expectEqual(world.reports[1].severity, "medium")
			T.expectEqual(
				Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), limit - 0.01),
				nil,
				"juste avant la borne"
			)
			T.expectEqual(
				Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), limit),
				115,
				"refus a relancé la cadence ou borne trop stricte"
			)
		end)

		T.it("accepte le client honnête le plus rapide : touche à EquipTime pile, sans violation", function()
			local Validator, makePlayer, _, world = setup()
			local a = makePlayer(Vector3.zero)
			local b = makePlayer(Vector3.new(5, 0, 0))
			equip(a, "AWP", nil, 10)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 11.58), 115)
			local knifer = makePlayer(Vector3.zero)
			equip(knifer, "M9Bayonet", nil, 20)
			-- Piste Equip du couteau : 1 s à vitesse 1,3, soit 0,769 s, à peine sous EquipTime (0,77)
			T.expectEqual(Validator.authorizeMelee(knifer, b.Character, "primary", 20 + 1 / 1.3), 50)
			T.expectEqual(#world.reports, 0)
		end)

		T.it("refuse un coup de couteau pendant l'equip, catégorie Melee", function()
			local Validator, makePlayer, _, world = setup()
			local a = makePlayer(Vector3.zero)
			local b = makePlayer(Vector3.new(5, 0, 0))
			equip(a, "M9Bayonet", nil, 10)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10.2), nil)
			T.expectEqual(world.reports[1].check, "equip")
			T.expectEqual(world.reports[1].category, "Melee")
			T.expectEqual(
				Validator.authorizeMelee(a, b.Character, "primary", 10.6),
				50,
				"cadence relancée par le refus"
			)
		end)

		T.it("repart de zéro à chaque equip, et refuse une arme dont l'arrivée n'a pas été vue", function()
			local Validator, makePlayer, _, world = setup()
			local a = makePlayer(Vector3.zero)
			local b = makePlayer(Vector3.new(5, 0, 0))
			local awp = equip(a, "AWP", nil, 10)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 12), 115)
			Validator.noteUnequip(a, awp, 13)
			awp.Parent = nil
			equip(a, "M9Bayonet", nil, 13)
			a.Character:FindFirstChildOfClass("Tool"):Destroy()
			equip(a, "AWP", nil, 14)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 14.5), nil, "rééquipée")
			-- Outil en main sans arrivée notée (aucun chemin du jeu) : refusé, jamais accepté en silence
			a.Character:FindFirstChildOfClass("Tool"):Destroy()
			local stray = Instance.new("Tool")
			stray.Name = "AWP"
			stray.Parent = a.Character
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 100), nil, "equip non vu")
			T.expectEqual(string.find(world.reports[#world.reports].detail, "sans equip vu", 1, true) ~= nil, true)
		end)

		T.it("ne gêne pas les bots : tir dès la sortie de l'arme accepté", function()
			local Validator, makePlayer, makeBot, world = setup()
			local bot = makeBot(Vector3.zero)
			local b = makePlayer(Vector3.new(50, 0, 0))
			equip(bot, "AWP", nil, 10)
			T.expectEqual(Validator.authorizeHitscan(bot, b.Character, rootOf(b.Character), 10), 115)
			local knifeBot = makeBot(Vector3.zero)
			equip(knifeBot, "M9Bayonet", nil, 10)
			T.expectEqual(
				Validator.authorizeMelee(knifeBot, makePlayer(Vector3.new(5, 0, 0)).Character, "primary", 10),
				50
			)
			T.expectEqual(#world.reports, 0)
		end)
	end)

	T.describe("Validator : chargeur (#175)", function()
		-- Cette méthode permet de tirer n touches honnêtes, une par cadence, lorsqu'un test vide un chargeur ; elle
		-- renvoie l'instant du dernier tir.
		local function fire(Validator, a, b, n: number, from: number): number
			local t = from
			for i = 1, n do
				t = from + (i - 1) * 1.5
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), t), 115, "tir " .. i)
			end
			return t
		end

		T.it("refuse le 6e tir sans rechargement, sans relancer la cadence", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			local last = fire(Validator, a, b, 5, 10)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 1.5), nil, "6e tir")
			T.expectEqual(world.reports[1].check, "magazine")
			T.expectEqual(world.reports[1].category, "Hitscan")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 100), nil, "plus tard")
		end)

		T.it("accepte 5 tirs après un rechargement complet, à ReloadTime moins la tolérance", function()
			local Validator, makePlayer, _, world, ShotRules = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			local last = fire(Validator, a, b, 5, 10)
			local reloadAt = last + 1.5
			Validator.noteReload(a, reloadAt)
			local ready = reloadAt + 3.7 - ShotRules.RELOAD_TOLERANCE
			T.expectEqual(
				Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), ready - 0.01),
				nil,
				"rechargement trop court"
			)
			T.expectEqual(#world.reports, 1)
			last = fire(Validator, a, b, 5, ready)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 1.5), nil, "11e tir")
		end)

		T.it("client honnête : rechargement à ReloadTime pile, chargeur partiel compris, sans violation", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			local last = fire(Validator, a, b, 3, 10)
			Validator.noteReload(a, last + 1.5)
			last = fire(Validator, a, b, 5, last + 1.5 + 3.7)
			Validator.noteReload(a, last + 1.5)
			fire(Validator, a, b, 5, last + 1.5 + 3.7)
			T.expectEqual(#world.reports, 0)
		end)

		T.it("annule le rechargement au changement d'arme, garde un rechargement déjà fini", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			local last = fire(Validator, a, b, 5, 10)
			local awp = a.Character:FindFirstChildOfClass("Tool")
			Validator.noteReload(a, last + 1.5)
			-- Couteau sorti 1 s après le début du rechargement, AWP ressortie : rechargement perdu
			Validator.noteUnequip(a, awp, last + 2.5)
			awp.Parent = nil
			local knife = equip(a, "M9Bayonet", nil, last + 2.5)
			Validator.noteUnequip(a, knife, last + 3)
			knife:Destroy()
			awp.Parent = a.Character
			Validator.noteEquip(a, awp, last + 3)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 20), nil, "annulé")
			-- Rechargement complet puis changement d'arme : acquis
			Validator.noteReload(a, last + 21)
			Validator.noteUnequip(a, awp, last + 25)
			Validator.noteEquip(a, awp, last + 25)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 30), 115, "acquis")
		end)

		T.it(
			"Reload arrivé en retard puis changement d'arme dès la fin : rechargement acquis, pas de chargeur refusé",
			function()
				local Validator, makePlayer, _, world, ShotRules = setup()
				local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
				local last = fire(Validator, a, b, 5, 10)
				local awp = a.Character:FindFirstChildOfClass("Tool")
				-- Reload envoyé à last + 1,5 mais reçu 0,6 s plus tard ; le client finit à last + 5,2 et range l'AWP aussitôt
				Validator.noteReload(a, last + 2.1)
				Validator.noteUnequip(a, awp, last + 5.25)
				Validator.noteEquip(a, awp, last + 6)
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 7.6), 115)
				T.expectEqual(#world.reports, 0)
				-- Rechargement vraiment interrompu (plus d'une marge avant sa fin) : annulé
				last = fire(Validator, a, b, 4, last + 9.1)
				Validator.noteReload(a, last + 1.5)
				Validator.noteUnequip(a, awp, last + 1.5 + 3.7 - ShotRules.RELOAD_CANCEL_TOLERANCE - 0.1)
				Validator.noteEquip(a, awp, last + 6)
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 8), nil)
			end
		)

		T.it("compte un Reload envoyé juste après un tir à partir de la fin de la cadence", function()
			local Validator, makePlayer, _, _, ShotRules = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			local last = fire(Validator, a, b, 5, 10)
			Validator.noteReload(a, last + 0.01) -- client modifié : le client attend FireDelay (1,46 s)
			local ready = last + 60 / 41 - ShotRules.RELOAD_TOLERANCE + 3.7 - ShotRules.RELOAD_TOLERANCE
			T.expectEqual(
				Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 3.6),
				nil,
				"sans cadence"
			)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), ready - 0.05), nil)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), ready + 0.01), 115)
		end)

		T.it("refuse une touche pendant un rechargement inachevé, chargeur non vide compris", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			local last = fire(Validator, a, b, 2, 10)
			Validator.noteReload(a, last + 1.5)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 3), nil)
			T.expectEqual(world.reports[1].check, "magazine")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 5.2), 115, "fini")
		end)

		T.it("Reload renvoyé en boucle sans jamais attendre : tir continu impossible", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			-- Client modifié : tire à pleine cadence et envoie Reload toutes les 3,5 s (ReloadTime - tolérance)
			local accepted = 0
			local nextReload = 10
			for i = 0, 40 do
				local t = 10 + i * 1.5
				if t >= nextReload then
					Validator.noteReload(a, nextReload)
					nextReload += 3.5
				end
				if Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), t) then
					accepted += 1
				end
			end
			-- 60 s de tir continu : 41 tirs voulus ; un client honnête en place 5 par cycle de 5 × 1,46 + 3,7 s
			T.expect(accepted <= 5, "touches acceptées : " .. accepted)
		end)

		T.it("compte un rechargement lancé pendant l'equip à partir de la fin de l'equip", function()
			local Validator, makePlayer, _, _, ShotRules = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			local last = fire(Validator, a, b, 5, 10)
			local awp = a.Character:FindFirstChildOfClass("Tool")
			Validator.noteUnequip(a, awp, last + 2)
			Validator.noteEquip(a, awp, last + 2)
			Validator.noteReload(a, last + 2) -- dès la sortie, pendant l'equip
			local equipEnd = last + 2 + 1.58 - ShotRules.EQUIP_TOLERANCE
			local ready = equipEnd + 3.7 - ShotRules.RELOAD_TOLERANCE
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), ready - 0.05), nil)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), ready), 115)
		end)

		T.it("suit le chargeur par joueur, et l'oublie à la réapparition", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			local other = makePlayer(Vector3.new(0, 0, 10), "AWP")
			local last = fire(Validator, a, b, 5, 10)
			T.expectEqual(
				Validator.authorizeHitscan(other, b.Character, rootOf(b.Character), last),
				115,
				"autre joueur"
			)
			Validator.forget(a)
			a.Character:FindFirstChildOfClass("Tool"):Destroy()
			equip(a, "AWP")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last + 1.5), 115)
		end)

		T.it("ne compte pas les tirs des bots : aucun tir de bot refusé au-delà de 5", function()
			local Validator, makePlayer, makeBot, world = setup()
			local bot = makeBot(Vector3.zero, "AWP")
			local b = makePlayer(Vector3.new(50, 0, 0))
			for i = 1, 12 do
				T.expectEqual(
					Validator.authorizeHitscan(bot, b.Character, rootOf(b.Character), i * 1.5),
					115,
					"tir " .. i
				)
			end
			T.expectEqual(#world.reports, 0)
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

	T.describe("Validator : validation des tirs de joueur (#174)", function()
		-- Cette méthode permet de préparer un tireur à l'AWP, une cible à 100 studs et sa tête lorsqu'un test valide un
		-- tir ; modes : contrôles à forcer (ex. { direction = "block" }), les autres gardent leur défaut.
		local function setupShot(modes: { [string]: string }?)
			local Validator, makePlayer, makeBot, world, ShotRules = setup()
			for check, mode in modes or {} do
				ShotRules.MODES[check] = mode
			end
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(100, 0, 0))
			local head = addPart(b.Character, "Head", Vector3.new(0, 2, 0))
			return Validator, a, b, head, world, makeBot, ShotRules
		end

		-- Tous les contrôles bloquants : le cas le plus strict pour un tir honnête ou un tir de bot.
		local ALL_BLOCK = {
			shape = "block",
			origin = "block",
			direction = "block",
			distance = "block",
			lineOfSight = "block",
		}

		-- Cette méthode permet de construire un tir de a vers un point, avec un impact annoncé (le point par défaut).
		local function shotToward(a, point: Vector3, hitPos: Vector3?, shotTime: number?)
			local origin = rootOf(a.Character).Position + EYE
			return {
				origin = origin,
				direction = (point - origin).Unit,
				hitPos = hitPos or point,
				shotTime = shotTime or 100,
			}
		end

		-- Cette méthode permet de lister les contrôles signalés au journal lorsqu'un test les vérifie.
		local function reportedChecks(world): string
			local checks = {}
			for _, report in world.reports do
				table.insert(checks, report.check)
			end
			return table.concat(checks, ",")
		end

		T.it("accepte un tir honnête sans aucune violation, contrôles bloquants", function()
			local Validator, a, b, head, world = setupShot(ALL_BLOCK)
			local damage, isHeadshot = Validator.authorizeHitscan(a, b.Character, head, 0, shotToward(a, head.Position))
			T.expectEqual(damage, 460)
			T.expectEqual(isHeadshot, true)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it("livre origine, direction et ligne de vue en journal seul, forme et distance bloquantes", function()
			local _, _, _, _, _, _, ShotRules = setupShot()
			T.expectEqual(ShotRules.MODES.origin, "log")
			T.expectEqual(ShotRules.MODES.direction, "log")
			T.expectEqual(ShotRules.MODES.lineOfSight, "log")
			T.expectEqual(ShotRules.MODES.shape, "block")
			T.expectEqual(ShotRules.MODES.distance, "block")
		end)

		T.it("refuse un tir de joueur sans origine ni direction (forme), en violation forte", function()
			local Validator, a, b, head, world = setupShot()
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, false), nil)
			T.expectEqual(reportedChecks(world), "shape")
			T.expectEqual(world.reports[1].severity, "high")
		end)

		T.it("refuse une direction non unitaire sans démarrer la cadence", function()
			local Validator, a, b, head, world = setupShot()
			local shot = shotToward(a, head.Position)
			shot.direction *= 3
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 10, shot), nil)
			T.expectEqual(reportedChecks(world), "shape")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 10.1, shotToward(a, head.Position)), 460)
		end)

		T.it("tir sur une cible non visée : journalisé en mode log, refusé en mode block", function()
			-- Silent aim : impact annoncé sur la tête, rayon tiré à 30 studs de là
			local Validator, a, b, head, world = setupShot()
			local shot = shotToward(a, head.Position + Vector3.new(0, 0, 30), head.Position)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shot), 460, "mode log : tir appliqué")
			T.expectEqual(reportedChecks(world), "direction")
			T.expectEqual(world.reports[1].severity, "medium")

			Validator, a, b, head, world = setupShot({ direction = "block" })
			shot = shotToward(a, head.Position + Vector3.new(0, 0, 30), head.Position)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shot), nil, "mode block : tir refusé")
			T.expectEqual(reportedChecks(world), "direction")
		end)

		T.it("refuse en mode block un rayon qui passe à côté de la partie (hitbox agrandie)", function()
			local Validator, a, b, head, world = setupShot({ direction = "block" })
			-- Rayon à 6 studs de la tête, impact pris sur ce rayon : au-delà du rayon de la partie + tolérance
			local aim = head.Position + Vector3.new(0, 0, 6)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotToward(a, aim)), nil)
			T.expectEqual(reportedChecks(world), "direction")
		end)

		T.it("tir derrière un mur : journalisé en mode log, refusé en mode block", function()
			local Validator, a, b, head, world = setupShot()
			world.obstructed = true
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotToward(a, head.Position)), 460)
			T.expectEqual(reportedChecks(world), "lineOfSight")

			Validator, a, b, head, world = setupShot({ lineOfSight = "block" })
			world.obstructed = true
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotToward(a, head.Position)), nil)
			T.expectEqual(reportedChecks(world), "lineOfSight")
		end)

		T.it("origine loin du tireur : journalisée en mode log, refusée en mode block", function()
			for _, mode in { "log", "block" } do
				local Validator, a, b, head, world = setupShot({ origin = mode })
				local shot = shotToward(a, head.Position)
				shot.origin = head.Position - Vector3.new(10, 0, 0)
				shot.direction = Vector3.new(1, 0, 0)
				T.expectEqual(
					Validator.authorizeHitscan(a, b.Character, head, 0, shot),
					if mode == "log" then 460 else nil,
					mode
				)
				T.expectEqual(reportedChecks(world), "origin", mode)
			end
		end)

		T.it("tolère l'origine d'un tireur rapide (surf) selon sa vitesse dans l'historique", function()
			local Validator, a, b, head, world = setupShot(ALL_BLOCK)
			-- 200 studs/s vers +X : la caméra du client est 10 studs devant la racine serveur
			world.histories[a.Character] = function(t)
				return Vector3.new(200 * (t - world.now), 0, 0)
			end
			local shot = shotToward(a, head.Position)
			shot.origin += Vector3.new(10, 0, 0)
			shot.direction = (head.Position - shot.origin).Unit
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shot), 460)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it("refuse au-delà de 250 studs un tir derrière un mur, même en journal seul", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(600, 0, 0))
			local head = addPart(b.Character, "Head", Vector3.new(0, 2, 0))
			world.obstructed = true
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotToward(a, head.Position)), nil)
			T.expectEqual(reportedChecks(world), "lineOfSight")
			T.expect(string.find(world.reports[1].detail, "refusé", 1, true) ~= nil, "refus non indiqué au journal")
		end)

		T.it("teste la ligne de vue jusqu'à la partie quand l'impact forgé est près de l'origine", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(600, 0, 0))
			local head = addPart(b.Character, "Head", Vector3.new(0, 2, 0))
			world.obstructed = true
			local shot = shotToward(a, head.Position)
			shot.hitPos = shot.origin + shot.direction * 0.3
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shot), nil, "mur contourné")
			T.expect(string.find(reportedChecks(world), "lineOfSight", 1, true) ~= nil, "ligne de vue non testée")
		end)

		T.it("applique un tir lointain dont seule la visée échoue, en journal seul", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(600, 0, 0))
			local head = addPart(b.Character, "Head", Vector3.new(0, 2, 0))
			local shot = shotToward(a, head.Position + Vector3.new(0, 0, 30), head.Position)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shot), 460)
			T.expectEqual(reportedChecks(world), "direction")
		end)

		T.it("refuse un tir au-delà de la portée du client", function()
			local Validator, a, b, head, world = setupShot()
			local shot = shotToward(a, head.Position)
			shot.hitPos = shot.origin + shot.direction * 3000
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shot), nil)
			T.expect(string.find(reportedChecks(world), "distance") ~= nil, "distance non signalée")
		end)

		T.it("vise la cible rembobinée à shotTime - INTERP_DELAY, pas sa position actuelle", function()
			local Validator, a, b, head, world = setupShot({ direction = "block" })
			-- La cible était à Z = 0 jusqu'à now - 0,02 s, puis a été posée 40 studs plus loin
			world.histories[b.Character] = function(t)
				return if t < world.now - 0.02 then Vector3.new(100, 0, 0) else Vector3.new(100, 0, 40)
			end
			rootOf(b.Character).Position = Vector3.new(100, 0, 40)
			head.Position = Vector3.new(100, 2, 40)
			local seen = Vector3.new(100, 2, 0)
			T.expectEqual(
				Validator.authorizeHitscan(a, b.Character, head, 10, shotToward(a, seen)),
				460,
				"vue du client"
			)
			T.expectEqual(reportedChecks(world), "")
			T.expectEqual(
				Validator.authorizeHitscan(a, b.Character, head, 20, shotToward(a, head.Position)),
				nil,
				"position actuelle, que le tireur ne voyait pas encore"
			)
		end)

		T.it("borne le rembobinage : un shotTime très ancien ne rend pas une position ancienne", function()
			local Validator, a, b, head, world = setupShot({ direction = "block" })
			-- Il y a plus de 0,4 s la cible était 40 studs plus loin ; le client réclame cet instant
			world.histories[b.Character] = function(t)
				return if t < world.now - 0.4 then Vector3.new(100, 0, 40) else Vector3.new(100, 0, 0)
			end
			local old = Vector3.new(100, 2, 40)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotToward(a, old, nil, 90)), nil)
		end)

		T.it("refuse une cible morte même si son historique répond encore (corps en place)", function()
			local Validator, a, b, head, world = setupShot()
			world.histories[b.Character] = function()
				return Vector3.new(100, 0, 0)
			end
			b.Character:FindFirstChildWhichIsA("Humanoid").Health = 0
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotToward(a, head.Position)), nil)
		end)

		T.it("refuse les tirs de joueurs tant que le monde n'est pas branché, pas ceux des bots", function()
			local owners = {}
			local loader = Loader.new({
				Players = {
					GetPlayerFromCharacter = function(_, character)
						return owners[character]
					end,
				},
			}, { warn = function() end })
			local Real = loader:require("src/server/Validator")
			local Participants = loader:require("src/server/Participants")
			local player = { UserId = 1, Name = "Joueur", Character = makeCharacter(Vector3.zero) }
			owners[player.Character] = player
			equip(player, "AWP")
			local bot = Participants.addBot("Marcel")
			local target = makeCharacter(Vector3.new(10, 0, 0))
			Participants.setCharacter(bot, target)
			local shot = shotToward(player, Vector3.new(10, 0, 0))
			T.expectEqual(Real.authorizeHitscan(Participants.fromPlayer(player), target, rootOf(target), 0, shot), nil)
			-- Le bot riposte : son tir ne dépend pas du monde
			bot.Character = target
			equip(bot, "AWP")
			T.expectEqual(Real.authorizeHitscan(bot, player.Character, rootOf(player.Character), 0), 115)
		end)

		T.it("garde la portée des bots à 250 studs entre racines, comme avant #174", function()
			local Validator, makePlayer, makeBot = setup()
			local bot = makeBot(Vector3.zero, "AWP")
			local near, far = makePlayer(Vector3.new(249, 0, 0)), makePlayer(Vector3.new(251, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(bot, near.Character, rootOf(near.Character), 0), 115)
			T.expectEqual(Validator.authorizeHitscan(bot, far.Character, rootOf(far.Character), 2), nil)
		end)

		T.it("ne refuse aucun tir de bot, tous contrôles bloquants, et ne journalise rien", function()
			local Validator, _, b, head, world, makeBot = setupShot(ALL_BLOCK)
			world.obstructed = true
			local bot = makeBot(Vector3.new(0, 0, 0), "AWP")
			T.expectEqual(Validator.authorizeHitscan(bot, b.Character, head, 0), 460, "tir de bot refusé")
			T.expectEqual(Validator.authorizeHitscan(bot, b.Character, rootOf(b.Character), 2), 115, "second tir")
			T.expectEqual(reportedChecks(world), "")
		end)
	end)

	T.describe("Validator : orientation et ligne de vue de la mêlée (#176)", function()
		-- Cette méthode permet de préparer un tireur au couteau à l'origine, tourné vers facing, et une cible à 5 studs
		-- devant lui (vers +X) lorsqu'un test valide un coup ; modes : contrôles à forcer, les autres gardent leur défaut.
		local function setupMelee(facing: Vector3?, modes: { [string]: string }?)
			local Validator, makePlayer, makeBot, world, ShotRules = setup()
			for check, mode in modes or {} do
				ShotRules.MODES[check] = mode
			end
			local a = makePlayer(Vector3.zero, "M9Bayonet", nil, facing or Vector3.new(1, 0, 0))
			-- La cible regarde le tireur : pas de backstab, 50 dégâts au slash
			local b = makePlayer(Vector3.new(5, 0, 0), nil, nil, Vector3.new(-1, 0, 0))
			return Validator, a, b, world, makeBot, ShotRules, makePlayer
		end

		local ALL_BLOCK = { orientation = "block", meleeLineOfSight = "block" }

		-- Cette méthode permet de lister les contrôles signalés au journal lorsqu'un test les vérifie.
		local function reportedChecks(world): string
			local checks = {}
			for _, report in world.reports do
				table.insert(checks, report.check)
			end
			return table.concat(checks, ",")
		end

		T.it("accepte un coup honnête face à la cible sans aucune violation, contrôles bloquants", function()
			local Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it(
			"coup dans le dos du tireur : journalisé en mode log, refusé en mode block sans relancer la cadence",
			function()
				-- Le tireur regarde vers -X, la cible est derrière lui
				local Validator, a, b, world = setupMelee(Vector3.new(-1, 0, 0))
				T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50, "mode log : coup appliqué")
				T.expectEqual(reportedChecks(world), "orientation")
				T.expectEqual(world.reports[1].category, "Melee")
				T.expectEqual(world.reports[1].severity, "medium")
				T.expect(string.find(world.reports[1].detail, "journal seul", 1, true) ~= nil, "mode non indiqué")

				Validator, a, b, world = setupMelee(Vector3.new(-1, 0, 0), ALL_BLOCK)
				T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10), nil, "mode block : coup refusé")
				T.expectEqual(reportedChecks(world), "orientation")
				-- Le tireur se retourne : la cadence n'a pas été relancée par le refus
				rootOf(a.Character).CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(1, 0, 0))
				T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 10.1), 50, "cadence relancée")
			end
		)

		T.it("coup sur le côté au-delà de l'angle permis : refusé en mode block", function()
			-- Cible à 90° du cap, à 7 studs : permis 70° + asin(2 / 7) ≈ 86,6°
			local Validator, a, _, world, _, _, makePlayer = setupMelee(Vector3.new(1, 0, 0), ALL_BLOCK)
			local side = makePlayer(Vector3.new(0, 0, 7))
			T.expectEqual(Validator.authorizeMelee(a, side.Character, "primary", 0), nil)
			T.expectEqual(reportedChecks(world), "orientation")
		end)

		T.it("coup à travers un mur : journalisé en mode log, refusé en mode block", function()
			local Validator, a, b, world = setupMelee()
			world.obstructed = true
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50, "mode log : coup appliqué")
			T.expectEqual(reportedChecks(world), "meleeLineOfSight")
			T.expectEqual(world.reports[1].category, "Melee")

			Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			world.obstructed = true
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil, "mode block : coup refusé")
			T.expectEqual(reportedChecks(world), "meleeLineOfSight")
		end)

		T.it("accepte un coup par-dessus un obstacle bas : la ligne œil à œil est dégagée", function()
			local Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			-- Caisse basse : seul le segment à hauteur des racines (Y = 0) la traverse
			world.obstructed = function(from: Vector3)
				return from.Y < 1
			end
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it("accepte une cible qui contourne le tireur : vue devant lui avant le rembobinage", function()
			local Validator, a, b, world = setupMelee(Vector3.new(1, 0, 0), ALL_BLOCK)
			-- La cible était devant (+X) jusqu'à now - 0,15 s, elle est maintenant passée dans le dos du tireur
			world.histories[b.Character] = function(t)
				return if t < world.now - 0.15 then Vector3.new(5, 0, 0) else Vector3.new(-4, 0, 0)
			end
			-- Elle fait face au tireur (pas de backstab)
			rootOf(b.Character).Position = Vector3.new(-4, 0, 0)
			rootOf(b.Character).CFrame = CFrame.lookAt(Vector3.new(-4, 0, 0), Vector3.zero)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it("accepte un tireur qui tourne : cible à 60° de son cap relayé", function()
			local Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			-- Cap relayé en retard : 60° à côté de la cible à 5 studs
			local yaw = math.rad(60)
			rootOf(a.Character).CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(math.cos(yaw), 0, math.sin(yaw)))
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it("élargit l'angle au contact : cible collée sur le côté acceptée", function()
			local Validator, a, _, world, _, _, makePlayer = setupMelee(Vector3.new(1, 0, 0), ALL_BLOCK)
			-- 100° du cap à 2,1 studs : permis 70° + asin(2 / 2,1) ≈ 142°
			local yaw = math.rad(100)
			local close = makePlayer(Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * 2.1)
			T.expectEqual(Validator.authorizeMelee(a, close.Character, "primary", 0), 50)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it("borne le rembobinage : une cible devant le tireur il y a plus de 0,4 s est refusée", function()
			local Validator, a, b, world = setupMelee(Vector3.new(1, 0, 0), ALL_BLOCK)
			world.histories[b.Character] = function(t)
				return if t < world.now - 0.4 then Vector3.new(5, 0, 0) else Vector3.new(-5, 0, 0)
			end
			rootOf(b.Character).Position = Vector3.new(-5, 0, 0)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil)
			T.expectEqual(reportedChecks(world), "orientation")
		end)

		T.it("teste la ligne de vue sur une position devant le tireur, pas derrière lui", function()
			local Validator, a, b, world = setupMelee(Vector3.new(1, 0, 0), ALL_BLOCK)
			-- Devant le tireur (+X), la cible n'était vue qu'à travers un mur ; dégagée seulement dans son dos : refusé
			world.histories[b.Character] = function(t)
				return if t < world.now - 0.2 then Vector3.new(5, 0, 0) else Vector3.new(-5, 0, 0)
			end
			world.obstructed = function(_, delta: Vector3)
				return delta.X > 0
			end
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil)
			T.expectEqual(reportedChecks(world), "meleeLineOfSight")
		end)

		T.it(
			"ignore les positions rembobinées hors de portée : pas de coup à travers un mur via le sillage",
			function()
				local Validator, a, b, world = setupMelee(Vector3.new(1, 0, 0), ALL_BLOCK)
				-- Cible en surf : à 30 studs à découvert il y a 0,3 s, maintenant à 5 studs derrière un mur
				world.histories[b.Character] = function(t)
					return if t < world.now - 0.25 then Vector3.new(30, 0, 0) else Vector3.new(5, 0, 0)
				end
				world.obstructed = function(_, delta: Vector3)
					return delta.Magnitude < 10
				end
				T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil)
				T.expectEqual(reportedChecks(world), "meleeLineOfSight")
			end
		)

		T.it("refuse une cible morte même si son historique répond encore (corps en place)", function()
			local Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			world.histories[b.Character] = function()
				return Vector3.new(5, 0, 0)
			end
			b.Character:FindFirstChildWhichIsA("Humanoid").Health = 0
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it("ne refuse aucun coup de bot, de dos et à travers un mur, et ne journalise rien", function()
			local Validator, _, b, world, makeBot = setupMelee(nil, ALL_BLOCK)
			world.obstructed = true
			-- Bot tourné vers -X, dos à la cible (+X) derrière un mur
			local bot = makeBot(Vector3.zero, "M9Bayonet")
			rootOf(bot.character).CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(-1, 0, 0))
			T.expectEqual(Validator.authorizeMelee(bot, b.Character, "primary", 0), 50, "coup de bot refusé")
			T.expectEqual(Validator.authorizeMelee(bot, b.Character, "primary", 0.5), 50, "second coup")
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it("refuse les coups de joueurs tant que le monde n'est pas branché, pas ceux des bots", function()
			local owners = {}
			local loader = Loader.new({
				Players = {
					GetPlayerFromCharacter = function(_, character)
						return owners[character]
					end,
				},
			}, { warn = function() end })
			local Real = loader:require("src/server/Validator")
			local Participants = loader:require("src/server/Participants")
			local player =
				{ UserId = 1, Name = "Joueur", Character = makeCharacter(Vector3.zero, nil, Vector3.new(1, 0, 0)) }
			owners[player.Character] = player
			local knife = Instance.new("Tool")
			knife.Name = "M9Bayonet"
			knife.Parent = player.Character
			Real.noteEquip(Participants.fromPlayer(player :: any), knife, LONG_AGO)
			local bot = Participants.addBot("Marcel")
			local target = makeCharacter(Vector3.new(5, 0, 0), nil, Vector3.new(-1, 0, 0))
			Participants.setCharacter(bot, target)
			T.expectEqual(Real.authorizeMelee(Participants.fromPlayer(player :: any), target, "primary", 0), nil)
			local botKnife = Instance.new("Tool")
			botKnife.Name = "M9Bayonet"
			botKnife.Parent = target
			T.expectEqual(Real.authorizeMelee(bot, player.Character, "primary", 0), 50)
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
