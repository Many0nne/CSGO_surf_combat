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
		local ShotRules = loader:require("src/server/ShotRules")
		-- Monde simulé de la validation des tirs (#174) : horloge serveur, historiques (fonction t -> position par
		-- personnage, sinon pas d'historique), obstacle de la map, violations reçues.
		local world = { now = 100, histories = {}, obstructed = false, reports = {} }
		Real.setShotWorld({
			serverNow = function()
				return world.now
			end,
			positionAt = function(char, t)
				local history = world.histories[char]
				return if history then history(math.clamp(t, world.now - 0.4, world.now)) else nil
			end,
			isObstructed = function()
				return world.obstructed
			end,
			report = function(attacker, check, severity, detail)
				table.insert(
					world.reports,
					{ attacker = attacker, check = check, severity = severity, detail = detail }
				)
			end,
		})
		local nextUserId = 0
		local function participantOf(attacker)
			return if attacker.isBot then attacker else Participants.fromPlayer(attacker)
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
