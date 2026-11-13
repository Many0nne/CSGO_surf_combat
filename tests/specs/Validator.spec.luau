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
		-- personnage, sinon pas d'historique ; elle peut rendre aussi la pose : cap et accroupi, #213), obstacle de la map
		-- (booléen, ou fonction (from, delta) -> booléen), violations reçues, ping des joueurs (s, nil : inconnu, #214).
		-- judged : touches et coups soumis aux contrôles (#297), dans l'ordre ({ attacker, kind }).
		-- meleeObstructed (#292) : obstacle de la mêlée seule (murs d'air compris), nil : celui des tirs.
		local world = {
			now = 100,
			histories = {},
			obstructed = false :: any,
			meleeObstructed = nil :: boolean?,
			reports = {},
			ping = nil :: number?,
			judged = {},
		}
		Real.setShotWorld({
			serverNow = function()
				return world.now
			end,
			positionAt = function(char, t)
				local history = world.histories[char]
				if not history then
					return nil
				end
				return history(math.clamp(t, world.now - 0.4, world.now))
			end,
			pingOf = function(attacker)
				return if attacker.isBot then nil else world.ping
			end,
			judged = function(attacker, kind)
				table.insert(world.judged, { attacker = attacker, kind = kind })
			end,
			isObstructed = function(from, delta)
				if type(world.obstructed) == "function" then
					return world.obstructed(from, delta)
				end
				return world.obstructed
			end,
			isMeleeObstructed = function(from, delta)
				if world.meleeObstructed ~= nil then
					return world.meleeObstructed
				end
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
			-- Sans shot, un joueur tire comme notre client ; `false` envoie un tir sans shot (client modifié). Comme notre
			-- client, un joueur annonce d'abord son tir (ShotFired, même shotTime), compté s'il est prêt comme dans
			-- relayShot (#215) ; noShotFired : touche envoyée seule (client modifié, ShotFired écarté par le relais).
			authorizeHitscan = function(attacker, targetCharacter, hitPart, now, shot, noShotFired)
				if shot == nil and not attacker.isBot then
					shot = honestShot(attacker, hitPart)
				elseif shot == false then
					shot = nil
				end
				local participant = participantOf(attacker)
				if
					not attacker.isBot
					and not noShotFired
					and type(shot) == "table"
					and type(shot.shotTime) == "number"
					and Real.isReadyToFire(participant, now, shot.shotTime)
				then
					Real.noteShotFired(participant, shot.shotTime, now)
				end
				return Real.authorizeHitscan(participant, targetCharacter, hitPart, now, shot)
			end,
			-- Cette méthode permet d'annoncer un tir accepté par le relais (ShotFired) lorsqu'un test règle l'ordre
			-- d'arrivée lui-même : prêt (isReadyToFire), puis compté ; renvoie s'il a été accepté.
			shotFired = function(attacker, shotTime, now)
				local participant = participantOf(attacker)
				if not Real.isReadyToFire(participant, now, shotTime) then
					return false
				end
				Real.noteShotFired(participant, shotTime, now)
				return true
			end,
			honestShot = honestShot,
			hasEntries = function(attacker)
				return Real.hasEntries(participantOf(attacker))
			end,
			-- Sans hitTime, un joueur frappe comme notre client : à l'instant présent (#214) ; `false` envoie un coup sans
			-- instant (client modifié). Un bot n'envoie pas d'instant.
			authorizeMelee = function(attacker, targetCharacter, attackKind, now, hitTime)
				if hitTime == nil and not attacker.isBot then
					hitTime = world.now
				elseif hitTime == false then
					hitTime = nil
				end
				return Real.authorizeMelee(participantOf(attacker), targetCharacter, attackKind, now, hitTime)
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
			isReadyToFire = function(attacker, now)
				return Real.isReadyToFire(participantOf(attacker), now)
			end,
			-- Possession des armes (#267) branchée comme dans init.server (InventoryStore.ownsTool) : check reçoit le
			-- participant et le nom du Tool
			setOwnership = Real.setOwnership,
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

		T.it("compte chaque touche et chaque coup de joueur soumis aux contrôles (dénominateur, #297)", function()
			local Validator, makePlayer, makeBot, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(100, 0, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0), 115)
			T.expectEqual(#world.judged, 1)
			T.expectEqual(world.judged[1].kind, "shot")
			T.expectEqual(world.judged[1].attacker.id, a.UserId)
			-- Refusé avant les contrôles (cadence pas finie) : pas jugé
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0.01), nil)
			T.expectEqual(#world.judged, 1, "touche écartée avant les contrôles")
			-- Tir hors de la portée : écarté avant les contrôles
			local far = makePlayer(Vector3.new(Validator.MAX_HITSCAN_RANGE + 1, 0, 0))
			Validator.authorizeHitscan(makePlayer(Vector3.zero, "AWP"), far.Character, rootOf(far.Character), 10)
			T.expectEqual(#world.judged, 1, "hors de portée : pas jugé")
			-- Bot : pas soumis aux contrôles
			local bot = makeBot(Vector3.zero, "AWP")
			T.expectEqual(Validator.authorizeHitscan(bot, b.Character, rootOf(b.Character), 0), 115)
			T.expectEqual(#world.judged, 1, "un bot n'est pas jugé")
			-- Coup de mêlée
			local knife = makePlayer(Vector3.zero, "M9Bayonet")
			T.expectEqual(Validator.authorizeMelee(knife, makePlayer(Vector3.new(5, 0, 0)).Character, "primary", 0), 50)
			T.expectEqual(#world.judged, 2)
			T.expectEqual(world.judged[2].kind, "melee")
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

	T.describe("Validator : armes possédées (#267)", function()
		-- Cette méthode permet de brancher l'inventaire par défaut (AWP et Ka-Bar) pour tous, comme InventoryStore pour
		-- un joueur non admin et pour un bot, lorsqu'un test porte sur la possession.
		local function defaultInventory(Validator)
			local InventoryRules = Loader.new({}):require("src/shared/InventoryRules")
			local owned = InventoryRules.resolve(nil, false)
			Validator.setOwnership(function(_, toolName)
				return InventoryRules.ownsTool(owned, toolName)
			end)
		end

		T.it("refuse le coup d'un couteau non possédé, accepte celui d'un couteau possédé", function()
			local Validator, makePlayer = setup()
			defaultInventory(Validator)
			local b = makePlayer(Vector3.new(5, 0, 0))
			T.expectEqual(
				Validator.authorizeMelee(makePlayer(Vector3.zero, "M9Bayonet"), b.Character, "primary", 0),
				nil
			)
			T.expectEqual(Validator.authorizeMelee(makePlayer(Vector3.zero, "KaBar"), b.Character, "primary", 0), 50)
		end)

		T.it("refuse tir et relais d'une arme à distance non possédée", function()
			local Validator, makePlayer = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(100, 0, 0))
			Validator.setOwnership(function()
				return false
			end)
			T.expectEqual(Validator.isReadyToFire(a, 0), false)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 0), nil)
		end)

		T.it("lit la possession sur le nom du Tool, pas sur l'attribut WeaponName", function()
			local Validator, makePlayer = setup()
			defaultInventory(Validator)
			local a, b = makePlayer(Vector3.zero), makePlayer(Vector3.new(5, 0, 0))
			-- Tool hors catalogue qui se dirait Ka-Bar : non possédé
			equip(a, "Couteau", "KaBar")
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil)
		end)

		T.it("un bot armé de l'inventaire par défaut tire toujours", function()
			local Validator, makePlayer, makeBot = setup()
			defaultInventory(Validator)
			local a, bot = makePlayer(Vector3.new(100, 0, 0)), makeBot(Vector3.zero, "AWP")
			T.expectEqual(Validator.authorizeHitscan(bot, a.Character, rootOf(a.Character), 0), 115)
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

	T.describe("Validator : tirs comptés et touches rattachées (#215, #216)", function()
		local AWP_DELAY = 60 / 41

		-- Cette méthode permet de construire le tir honnête d'un joueur vers sa cible avec un instant donné lorsqu'un
		-- test règle lui-même l'ordre des remotes.
		local function shotAt(Validator, a, b, shotTime: number)
			local shot = Validator.honestShot(a, rootOf(b.Character))
			shot.shotTime = shotTime
			return shot
		end

		-- Cette méthode permet de lister les contrôles journalisés lorsqu'un test vérifie le journal.
		local function checks(world): { string }
			local out = {}
			for _, r in world.reports do
				table.insert(out, r.check)
			end
			return out
		end

		T.it(
			"6e ShotFired sans rechargement refusé (chargeur de l'AWP : 5), y compris après 4 tirs manqués",
			function()
				local Validator, makePlayer, _, world = setup()
				local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
				local t = 10
				-- 4 tirs manqués (ShotFired seuls), puis une touche : 5 tirs comptés
				for i = 1, 4 do
					T.expectEqual(Validator.shotFired(a, 100 + i, t), true, "tir manqué " .. i)
					t += 1.5
				end
				T.expectEqual(
					Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), t, shotAt(Validator, a, b, 105)),
					115
				)
				t += 1.5
				-- 6e : ShotFired refusé (donc non relayé), et sa touche aussi
				T.expectEqual(Validator.shotFired(a, 106, t), false, "6e ShotFired")
				T.expectEqual(
					Validator.authorizeHitscan(
						a,
						b.Character,
						rootOf(b.Character),
						t,
						shotAt(Validator, a, b, 106),
						true
					),
					nil,
					"6e touche"
				)
				T.expectEqual(table.concat(checks(world), ","), "magazine")
			end
		)

		T.it("rechargement fini puis tir accepté et compté", function()
			local Validator, makePlayer, _, world, ShotRules = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			local t = 10
			for i = 1, 5 do
				T.expectEqual(Validator.shotFired(a, 100 + i, t), true)
				t += 1.5
			end
			Validator.noteReload(a, t)
			local ready = t + 3.7 - ShotRules.RELOAD_TOLERANCE
			T.expectEqual(Validator.shotFired(a, 200, ready - 0.05), false, "rechargement inachevé")
			for i = 1, 5 do
				T.expectEqual(Validator.shotFired(a, 200 + i, ready + (i - 1) * 1.5), true, "après rechargement " .. i)
			end
			T.expectEqual(Validator.shotFired(a, 300, ready + 7.5), false, "chargeur de nouveau vide")
			T.expectEqual(#world.reports, 0, "un ShotFired refusé n'est pas journalisé")
		end)

		T.it("touche rattachée au bon tir, sans décompte de plus", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			-- Deux ShotFired en attente (client modifié ou tir manqué juste avant) : la touche va au sien
			T.expectEqual(Validator.shotFired(a, 100, 10), true)
			T.expectEqual(Validator.shotFired(a, 100.4, 10.4), true)
			local damage, _, linked = Validator.authorizeHitscan(
				a,
				b.Character,
				rootOf(b.Character),
				10.5,
				shotAt(Validator, a, b, 100),
				true
			)
			T.expectEqual(damage, 115)
			T.expectEqual(linked, 100, "rattachée au premier tir, pas au dernier")
			T.expectEqual(#world.reports, 0)
			-- 2 tirs comptés (pas 3) : encore 3 ShotFired avant le chargeur vide
			for i = 1, 3 do
				T.expectEqual(Validator.shotFired(a, 101 + i, 10.5 + i * 1.5), true, "tir " .. i + 2)
			end
			T.expectEqual(Validator.shotFired(a, 110, 16.5), false, "6e")
		end)

		T.it(
			"touche orpheline : journalisée (journal seul), appliquée, comptée dans le chargeur ; refusée en block",
			function()
				local Validator, makePlayer, _, world, ShotRules = setup()
				local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
				local damage, _, linked = Validator.authorizeHitscan(
					a,
					b.Character,
					rootOf(b.Character),
					10,
					shotAt(Validator, a, b, 100),
					true
				)
				T.expectEqual(damage, 115, "mode log : touche appliquée")
				T.expectEqual(linked, nil, "orpheline")
				T.expectEqual(#world.reports, 1)
				T.expectEqual(world.reports[1].check, "shotLink")
				T.expectEqual(world.reports[1].category, "Hitscan")
				T.expectEqual(world.reports[1].severity, "low")
				T.expect(string.find(world.reports[1].detail, "journal seul", 1, true) ~= nil, world.reports[1].detail)
				-- Le chargeur compte les touches orphelines : 4 de plus, puis la 6e est refusée
				for i = 1, 4 do
					T.expectEqual(
						Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 10 + i * 1.5, nil, true),
						115,
						"orpheline " .. i + 1
					)
				end
				T.expectEqual(
					Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 17.5, nil, true),
					nil,
					"6e"
				)
				T.expectEqual(Validator.shotFired(a, 999, 17.5), false, "ShotFired refusé aussi")
				-- Mode block : une touche orpheline est refusée
				local V2, makePlayer2, _, world2, ShotRules2 = setup()
				local c, d = makePlayer2(Vector3.zero, "AWP"), makePlayer2(Vector3.new(50, 0, 0))
				ShotRules2.MODES.shotLink = "block"
				T.expectEqual(V2.authorizeHitscan(c, d.Character, rootOf(d.Character), 10, nil, true), nil, "block")
				T.expectEqual(world2.reports[1].check, "shotLink")
				T.expectEqual(
					V2.authorizeHitscan(c, d.Character, rootOf(d.Character), 10),
					115,
					"rattachée : acceptée"
				)
				ShotRules2.MODES.shotLink = "log"
				T.expectEqual(ShotRules.MODES.shotLink, "log")
			end
		)

		T.it("touche refusée par ailleurs (chargeur vide) : pas de ligne shotLink en plus", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			for i = 1, 5 do
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 10 + (i - 1) * 1.5), 115)
			end
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 17.5), nil)
			T.expectEqual(table.concat(checks(world), ","), "magazine")
		end)

		T.it("deux touches pour un même tir d'AWP : une seule rattachée (pas de pénétration)", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			local other = makePlayer(Vector3.new(0, 0, 50))
			T.expectEqual(Validator.shotFired(a, 100, 10), true)
			local shot = shotAt(Validator, a, b, 100)
			local _, _, linked = Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 10.01, shot, true)
			T.expectEqual(linked, 100)
			-- Seconde touche du même tir (autre cible) : refusée par la cadence, jamais rattachée
			local otherShot = Validator.honestShot(a, rootOf(other.Character))
			otherShot.shotTime = 100
			local damage, _, secondLink =
				Validator.authorizeHitscan(a, other.Character, rootOf(other.Character), 10.02, otherShot, true)
			T.expectEqual(damage, nil)
			T.expectEqual(secondLink, nil)
			T.expectEqual(#world.reports, 0, "cadence : refus sans journal, comme avant")
		end)

		-- Roblox garantit l'ordre d'envoi entre deux RemoteEvent d'un même client : seul un client modifié (ou une file
		-- de Roblox saturée) inverse les deux ; aucun délai d'attente n'est donc accordé, mais rien n'est compté deux fois
		T.it("HitscanDamage avant son ShotFired : touche orpheline, tir compté une seule fois", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			for i = 1, 5 do
				local t = 10 + (i - 1) * 1.5
				T.expectEqual(
					Validator.authorizeHitscan(
						a,
						b.Character,
						rootOf(b.Character),
						t,
						shotAt(Validator, a, b, 100 + i),
						true
					),
					115,
					"touche " .. i .. " avant son tir"
				)
				-- Son ShotFired arrive juste après : relayé (son, recul 3P), pas recompté, même chargeur plein au 5e
				T.expectEqual(Validator.shotFired(a, 100 + i, t + 0.01), true, "ShotFired " .. i)
			end
			T.expectEqual(Validator.shotFired(a, 106, 17.5), false, "6e tir : 5 comptés, pas 10")
			T.expectEqual(#world.reports, 5, "chaque touche arrivée avant son tir est journalisée")
			for _, r in world.reports do
				T.expectEqual(r.check, "shotLink")
			end
		end)

		T.it("rechargement borné par la cadence du dernier tir compté, même manqué", function()
			local Validator, makePlayer, _, _, ShotRules = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			local last = 10
			for i = 1, 5 do
				last = 10 + (i - 1) * 1.5
				T.expectEqual(Validator.shotFired(a, 100 + i, last), true)
			end
			Validator.noteReload(a, last + 0.01) -- client modifié : recharge dès son dernier tir
			local ready = last + AWP_DELAY - ShotRules.RELOAD_TOLERANCE + 3.7 - ShotRules.RELOAD_TOLERANCE
			T.expectEqual(Validator.shotFired(a, 200, ready - 0.05), false)
			T.expectEqual(Validator.shotFired(a, 201, ready + 0.01), true)
		end)

		T.it("bots : tirs relayés jamais refusés ni comptés, aucune violation", function()
			local Validator, makePlayer, makeBot, world = setup()
			local bot = makeBot(Vector3.zero, "AWP")
			local b = makePlayer(Vector3.new(50, 0, 0))
			for i = 1, 12 do
				T.expectEqual(Validator.shotFired(bot, nil, i * 1.5), true, "tir " .. i)
				T.expectEqual(Validator.authorizeHitscan(bot, b.Character, rootOf(b.Character), i * 1.5), 115)
			end
			T.expectEqual(#world.reports, 0)
		end)

		T.it("oublie les tirs récents à la réapparition", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			T.expectEqual(Validator.shotFired(a, 100, 10), true)
			T.expect(Validator.hasEntries(a), "registre tenu")
			Validator.forget(a)
			T.expectEqual(Validator.hasEntries(a), false)
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

		T.it(
			"tir à travers un mur d'air : jugé par la ligne de vue des tirs, pas celle de la mêlée (#292)",
			function()
				local Validator, a, b, head, world = setupShot({ lineOfSight = "block" })
				world.meleeObstructed = true
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotToward(a, head.Position)), 460)
				T.expectEqual(reportedChecks(world), "")
			end
		)

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

		T.it("mêlée jugée par sa propre ligne de vue : murs d'air compris, pas celle des tirs (#292)", function()
			-- Mur d'air entre les deux : il arrête le coup (comme chez le client), pas une balle
			local Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			world.meleeObstructed = true
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil, "coup à travers un mur d'air")
			T.expectEqual(reportedChecks(world), "meleeLineOfSight")

			-- Obstacle des seuls tirs : sans effet sur la mêlée
			Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			world.obstructed = true
			world.meleeObstructed = false
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50)
			T.expectEqual(reportedChecks(world), "")
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

		T.it(
			"accepte une cible qui contourne le tireur : vue devant lui à l'instant du coup (100 ms de ping)",
			function()
				local Validator, a, b, world =
					setupMelee(Vector3.new(1, 0, 0), { ping = "block", orientation = "block" })
				world.ping = 0.1
				-- La cible était devant (+X) jusqu'à now - 0,15 s, elle est maintenant passée dans le dos du tireur
				world.histories[b.Character] = function(t)
					return if t < world.now - 0.15 then Vector3.new(5, 0, 0) else Vector3.new(-4, 0, 0)
				end
				-- Elle fait face au tireur (pas de backstab)
				rootOf(b.Character).Position = Vector3.new(-4, 0, 0)
				rootOf(b.Character).CFrame = CFrame.lookAt(Vector3.new(-4, 0, 0), Vector3.zero)
				-- Coup parti il y a un aller simple (50 ms) plus une frame : le client voyait la cible à hitTime - INTERP_DELAY
				T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0, world.now - 0.06), 50)
				T.expectEqual(reportedChecks(world), "")
			end
		)

		T.it("accepte un tireur qui tourne : cible à 80° de son cap relayé, à 7 studs", function()
			local Validator, a, _, world, _, _, makePlayer = setupMelee(nil, ALL_BLOCK)
			-- Cap relayé en retard de 80° (~1 000°/s pendant 80 ms) ; permis à 7 studs : 70° + asin(2 / 7) ≈ 86,6°
			local far = makePlayer(Vector3.new(7, 0, 0), nil, nil, Vector3.new(-1, 0, 0))
			local yaw = math.rad(80)
			rootOf(a.Character).CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(math.cos(yaw), 0, math.sin(yaw)))
			T.expectEqual(Validator.authorizeMelee(a, far.Character, "primary", 0), 50)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it("ne rembobine qu'à l'instant du coup : deux raycasts pour une cible derrière un mur", function()
			local Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			world.histories[b.Character] = function()
				return Vector3.new(5, 0, 0)
			end
			local raycasts = 0
			world.obstructed = function()
				raycasts += 1
				return true
			end
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil)
			-- Une position (l'instant annoncé) : racine à racine et œil à tête
			T.expectEqual(raycasts, 2)
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
			-- Instant annoncé 0,5 s en arrière : ramené à now - 0,4 s, où la cible était déjà derrière
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0, world.now - 0.5), nil)
			T.expectEqual(reportedChecks(world), "orientation")
		end)

		T.it(
			"coup à l'ancienne position : instant hors du ping signalé, sinon cible prise derrière le tireur",
			function()
				-- La cible était devant (+X) jusqu'à now - 0,25 s, elle est maintenant dans le dos du tireur ; 30 ms de ping
				local function scene(modes)
					local Validator, a, b, world = setupMelee(Vector3.new(1, 0, 0), modes)
					world.ping = 0.03
					world.histories[b.Character] = function(t)
						return if t < world.now - 0.25 then Vector3.new(5, 0, 0) else Vector3.new(-5, 0, 0)
					end
					-- Elle fait face au tireur (pas de backstab)
					rootOf(b.Character).Position = Vector3.new(-5, 0, 0)
					rootOf(b.Character).CFrame = CFrame.lookAt(Vector3.new(-5, 0, 0), Vector3.zero)
					return Validator, a, b, world
				end
				-- Client modifié : annonce l'instant où la cible était devant lui (0,2 s, ping 30 ms)
				local Validator, a, b, world = scene(ALL_BLOCK)
				T.expectEqual(
					Validator.authorizeMelee(a, b.Character, "primary", 0, world.now - 0.2),
					50,
					"ping en journal"
				)
				T.expectEqual(reportedChecks(world), "ping")
				T.expectEqual(world.reports[1].category, "Melee")
				Validator, a, b, world = scene({ ping = "block" })
				T.expectEqual(
					Validator.authorizeMelee(a, b.Character, "primary", 0, world.now - 0.2),
					nil,
					"ping en block"
				)
				-- Instant honnête : la cible était déjà derrière lui
				Validator, a, b, world = scene(ALL_BLOCK)
				T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0, world.now - 0.02), nil)
				T.expectEqual(reportedChecks(world), "orientation")
			end
		)

		T.it("accepte un coup honnête sur une cible en mouvement, 50 et 150 ms de ping", function()
			for _, ping in { 0.05, 0.15 } do
				local Validator, a, b, world = setupMelee(Vector3.new(1, 0, 0), {
					ping = "block",
					orientation = "block",
					meleeLineOfSight = "block",
				})
				world.ping = ping
				-- Cible qui traverse le cône du tireur à 20 studs/s, de -Z vers +Z, à 5 studs devant lui
				world.histories[b.Character] = function(t)
					return Vector3.new(5, 0, (t - world.now) * 20 + 6)
				end
				rootOf(b.Character).Position = Vector3.new(5, 0, 6)
				-- Coup parti un aller simple plus une frame avant son arrivée ; la cible était alors devant le tireur
				local hitTime = world.now - ping / 2 - 0.016
				T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0, hitTime), 50, "ping " .. ping)
				T.expectEqual(reportedChecks(world), "")
			end
		end)

		T.it("refuse un coup de joueur sans instant (forme, violation forte)", function()
			local Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0, false), nil)
			T.expectEqual(reportedChecks(world), "shape")
			T.expectEqual(world.reports[1].severity, "high")
			T.expectEqual(world.reports[1].category, "Melee")
		end)

		T.it("prend l'œil du tireur accroupi : un obstacle bas que l'œil debout survolait bloque le coup", function()
			local Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			-- Caisse de 2 studs : l'œil debout (2,5) passe au-dessus, l'œil accroupi (1,2) non
			world.obstructed = function(from: Vector3)
				return from.Y < 2
			end
			world.histories[a.Character] = function()
				return Vector3.zero, 0, true
			end
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil)
			T.expectEqual(reportedChecks(world), "meleeLineOfSight")
		end)

		T.it("accepte un coup dont le paquet de position suivant, déjà tourné, est arrivé avant lui", function()
			local Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			-- Cap reçu en dernier : 150° de la cible (le joueur s'est retourné après le coup) ; 50 ms avant : face à elle
			local away = math.rad(150)
			rootOf(a.Character).CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(math.cos(away), 0, math.sin(away)))
			local yawOf = Loader.new():require("src/shared/CharacterSyncRules").yawOf
			local facingYaw, awayYaw =
				yawOf(Vector3.new(1, 0, 0)), yawOf(Vector3.new(math.cos(away), 0, math.sin(away)))
			world.histories[a.Character] = function(t)
				return Vector3.zero, if t < world.now - 0.03 then facingYaw else awayYaw, false
			end
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it("ne prend pas un cap plus ancien que deux paquets", function()
			local Validator, a, b, world = setupMelee(Vector3.new(-1, 0, 0), ALL_BLOCK)
			-- Face à la cible il y a 0,3 s seulement : dos tourné sur les caps récents
			local yawOf = Loader.new():require("src/shared/CharacterSyncRules").yawOf
			local facingYaw, awayYaw = yawOf(Vector3.new(1, 0, 0)), yawOf(Vector3.new(-1, 0, 0))
			world.histories[a.Character] = function(t)
				return Vector3.zero, if t < world.now - 0.25 then facingYaw else awayYaw, false
			end
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), nil)
			T.expectEqual(reportedChecks(world), "orientation")
		end)

		T.it("prend l'œil debout tant que la caméra du tireur qui s'accroupit descend encore", function()
			local Validator, a, b, world = setupMelee(nil, ALL_BLOCK)
			world.obstructed = function(from: Vector3)
				return from.Y < 2
			end
			-- Accroupi depuis 0,1 s seulement : la caméra est encore au-dessus de la caisse
			world.histories[a.Character] = function(t)
				return Vector3.zero, 0, t >= world.now - 0.1
			end
			T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0), 50)
			T.expectEqual(reportedChecks(world), "")
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
				-- Instant annoncé où la cible était à 30 studs : hors de portée, position actuelle derrière le mur
				T.expectEqual(Validator.authorizeMelee(a, b.Character, "primary", 0, world.now - 0.2), nil)
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

	T.describe("Validator : tir relayé aux autres clients (#156)", function()
		T.it("prêt avec une arme à distance sortie et chargée", function()
			local Validator, makePlayer = setup()
			local a = makePlayer(Vector3.zero, "AWP")
			T.expectEqual(Validator.isReadyToFire(a, 10), true)
		end)

		T.it("pas prêt sans arme, au couteau, ou avec une arme inconnue", function()
			local Validator, makePlayer = setup()
			T.expectEqual(Validator.isReadyToFire(makePlayer(Vector3.zero), 10), false, "sans arme")
			T.expectEqual(Validator.isReadyToFire(makePlayer(Vector3.zero, "M9Bayonet"), 10), false, "couteau")
			T.expectEqual(Validator.isReadyToFire(makePlayer(Vector3.zero, "Pistolet à eau"), 10), false, "inconnue")
		end)

		T.it("pas prêt pendant l'equip, prêt à EquipTime moins la tolérance", function()
			local Validator, makePlayer, _, _, ShotRules = setup()
			local a = makePlayer(Vector3.zero)
			local awp = Instance.new("Tool")
			awp.Name = "AWP"
			awp.Parent = a.Character
			Validator.noteEquip(a, awp, 10)
			local ready = 10 + 1.58 - ShotRules.EQUIP_TOLERANCE
			T.expectEqual(Validator.isReadyToFire(a, ready - 0.01), false, "pendant l'equip")
			T.expectEqual(Validator.isReadyToFire(a, ready + 0.01), true, "equip fini")
		end)

		T.it("pas prêt chargeur vidé ou rechargement inachevé, prêt une fois rechargé", function()
			local Validator, makePlayer, _, _, ShotRules = setup()
			local a, b = makePlayer(Vector3.zero, "AWP"), makePlayer(Vector3.new(50, 0, 0))
			local last = 10
			for i = 1, 5 do
				last = 10 + (i - 1) * 1.5
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), last), 115, "tir " .. i)
			end
			T.expectEqual(Validator.isReadyToFire(a, last + 1.5), false, "chargeur vidé")
			local reloadAt = last + 1.5
			Validator.noteReload(a, reloadAt)
			local ready = reloadAt + 3.7 - ShotRules.RELOAD_TOLERANCE
			T.expectEqual(Validator.isReadyToFire(a, ready - 0.01), false, "rechargement inachevé")
			T.expectEqual(Validator.isReadyToFire(a, ready + 0.01), true, "rechargé")
		end)

		T.it("ne journalise rien et ne relance pas la cadence d'une touche", function()
			local Validator, makePlayer, _, world = setup()
			local a, b = makePlayer(Vector3.zero), makePlayer(Vector3.new(50, 0, 0))
			local awp = Instance.new("Tool")
			awp.Name = "AWP"
			awp.Parent = a.Character
			Validator.noteEquip(a, awp, 9.9)
			T.expectEqual(Validator.isReadyToFire(a, 10), false, "pendant l'equip")
			T.expectEqual(#world.reports, 0, "aucune violation")
			T.expectEqual(Validator.isReadyToFire(a, 20), true)
			T.expectEqual(
				Validator.authorizeHitscan(a, b.Character, rootOf(b.Character), 20),
				115,
				"touche au même instant"
			)
		end)

		T.it("un contrôle d'equip en mode log ne rend pas muet un tir que la touche accepterait", function()
			local Validator, makePlayer, _, _, ShotRules = setup()
			local a = makePlayer(Vector3.zero)
			local awp = Instance.new("Tool")
			awp.Name = "AWP"
			awp.Parent = a.Character
			Validator.noteEquip(a, awp, 10)
			ShotRules.MODES.equip = "log"
			T.expectEqual(Validator.isReadyToFire(a, 10.1), true, "equip en journal seul")
			ShotRules.MODES.equip = "block"
			T.expectEqual(Validator.isReadyToFire(a, 10.1), false, "equip bloquant")
		end)

		T.it("toujours prêt pour un bot armé d'un fusil (BotArsenal fait respecter equip et chargeur)", function()
			local Validator, _, makeBot = setup()
			T.expectEqual(Validator.isReadyToFire(makeBot(Vector3.zero, "AWP"), 0), true)
			T.expectEqual(Validator.isReadyToFire(makeBot(Vector3.zero, "M9Bayonet"), 0), false, "couteau")
		end)
	end)
	T.describe("Validator : instant du tir borné par le ping (#214) et pose rembobinée (#213)", function()
		-- Cette méthode permet de préparer un tireur à l'AWP à l'origine et une cible à 100 studs (+X), qui regarde le
		-- tireur, lorsqu'un test vérifie l'instant ou la pose ; modes : contrôles à forcer.
		local function setupPose(modes: { [string]: string }?)
			local Validator, makePlayer, makeBot, world, ShotRules = setup()
			for check, mode in modes or {} do
				ShotRules.MODES[check] = mode
			end
			local a = makePlayer(Vector3.zero, "AWP")
			local b = makePlayer(Vector3.new(100, 0, 0), nil, nil, Vector3.new(-1, 0, 0))
			return Validator, a, b, world, ShotRules, makeBot
		end

		-- Cette méthode permet de construire le tir de a vers un point, annoncé à shotTime.
		local function shotAt(a, point: Vector3, shotTime: number)
			local origin = rootOf(a.Character).Position + EYE
			return { origin = origin, direction = (point - origin).Unit, hitPos = point, shotTime = shotTime }
		end

		-- Cette méthode permet de lister les contrôles signalés au journal lorsqu'un test les vérifie.
		local function reportedChecks(world): string
			local checks = {}
			for _, report in world.reports do
				table.insert(checks, report.check)
			end
			return table.concat(checks, ",")
		end

		-- Cap (rad) d'un personnage tourné vers look, comme CharacterSync le relaie.
		local yawOf = Loader.new():require("src/shared/CharacterSyncRules").yawOf

		T.it("accepte un tir honnête avec 50 et 150 ms de ping, sans violation", function()
			for _, ping in { 0.05, 0.15 } do
				local Validator, a, b, world = setupPose({ ping = "block", direction = "block" })
				world.ping = ping
				local head = addPart(b.Character, "Head", Vector3.new(0, 2, 0))
				-- Tir parti un aller simple plus deux frames avant son arrivée
				local shot = shotAt(a, head.Position, world.now - ping / 2 - 0.033)
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shot), 460, "ping " .. ping)
				T.expectEqual(reportedChecks(world), "")
			end
		end)

		T.it(
			"signale un shotTime 0,4 s en arrière avec 30 ms de ping : journal seul, refusé en mode block",
			function()
				local Validator, a, b, world = setupPose()
				world.ping = 0.03
				local head = addPart(b.Character, "Head", Vector3.new(0, 2, 0))
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotAt(a, head.Position, 99.6)), 460)
				T.expectEqual(reportedChecks(world), "ping")
				T.expect(string.find(world.reports[1].detail, "journal seul", 1, true) ~= nil, "mode non indiqué")
				T.expectEqual(world.reports[1].severity, "medium")

				Validator, a, b, world = setupPose({ ping = "block" })
				world.ping = 0.03
				head = addPart(b.Character, "Head", Vector3.new(0, 2, 0))
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotAt(a, head.Position, 99.6)), nil)
				T.expectEqual(reportedChecks(world), "ping")
			end
		)

		T.it("ne borne pas l'instant d'un joueur dont le ping est inconnu", function()
			local Validator, a, b, world = setupPose({ ping = "block" })
			local head = addPart(b.Character, "Head", Vector3.new(0, 2, 0))
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotAt(a, head.Position, 99.6)), 460)
			T.expectEqual(reportedChecks(world), "")
		end)

		T.it(
			"cible qui a tourné entre le tir et sa réception : main rembobinée là où le tireur la voyait",
			function()
				local Validator, a, b, world = setupPose({ direction = "block" })
				-- Rig serveur : la cible regarde le tireur (-X), sa main droite est à 2 studs côté -Z
				local hand = addPart(b.Character, "RightHand", Vector3.new(0, 0, -2))
				-- Au tir, elle tournait le dos au tireur (+X) : sa main droite était côté +Z
				local backYaw, faceYaw = yawOf(Vector3.new(1, 0, 0)), yawOf(Vector3.new(-1, 0, 0))
				world.histories[b.Character] = function(t)
					return Vector3.new(100, 0, 0), if t < world.now - 0.05 then backYaw else faceYaw, false
				end
				local seen = Vector3.new(100, 0, 2)
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, hand, 0, shotAt(a, seen, world.now)), 115)
				T.expectEqual(reportedChecks(world), "", "main vue par le tireur")
				-- La main là où le rig serveur la montre maintenant, que le tireur ne voyait pas : refusé
				T.expectEqual(
					Validator.authorizeHitscan(a, b.Character, hand, 10, shotAt(a, hand.Position, world.now)),
					nil
				)
				T.expectEqual(reportedChecks(world), "direction")
			end
		)

		T.it(
			"cible accroupie au tir, debout maintenant : tête rembobinée baissée (si le rig 3P s'accroupit)",
			function()
				local Validator, a, b, world, ShotRules = setupPose({ direction = "block" })
				-- Le rig 3P ne s'accroupit pas aujourd'hui (CROUCH_DROP = 0) : piste simulée qui baisse la tête de 3 studs
				ShotRules.CROUCH_DROP = 3
				local head = addPart(b.Character, "Head", Vector3.new(0, 2, 0))
				local faceYaw = yawOf(Vector3.new(-1, 0, 0))
				world.histories[b.Character] = function(t)
					return Vector3.new(100, 0, 0), faceYaw, t < world.now - 0.05
				end
				local seen = Vector3.new(100, -1, 0)
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotAt(a, seen, world.now)), 460)
				T.expectEqual(reportedChecks(world), "", "tête vue baissée")
				-- La tête debout, que le tireur ne voyait pas : refusé
				T.expectEqual(
					Validator.authorizeHitscan(a, b.Character, head, 10, shotAt(a, head.Position, world.now)),
					nil
				)
				T.expectEqual(reportedChecks(world), "direction")
			end
		)

		-- Bras gauche R15 des tests de membres (#240) : articulations (C0/C1) et tailles, au format ShotRules.ArmRig.
		local LEFT_ARM = {
			shoulderC1 = Vector3.new(0, 0.4, 0),
			elbowC0 = Vector3.new(0, -0.4, 0),
			elbowC1 = Vector3.new(0, 0.2, 0),
			wristC0 = Vector3.new(0, -0.5, 0),
			wristC1 = Vector3.new(0, 0.125, 0),
			upperArmSize = Vector3.new(1, 1.2, 1),
			lowerArmSize = Vector3.new(1, 1.1, 1),
			handSize = Vector3.new(1, 0.3, 1),
			shoulderC0 = Vector3.new(-1, 0.56, 0),
			waistC1 = CFrame.new(0, -0.78, 0),
		}

		-- Cette méthode permet d'ajouter un bras gauche R15 (UpperTorso, Waist, épaule, coude, poignet, d'après LEFT_ARM)
		-- à une cible lorsqu'un test tire sur un membre (#240) ; bras le long du corps, comme sur le rig serveur. Renvoie
		-- la main et la position de l'épaule.
		local function addLeftArm(character)
			local torso = addPart(character, "UpperTorso", Vector3.new(0, 1, 0))
			local shoulderPos = torso.Position + LEFT_ARM.shoulderC0
			-- Cette méthode permet de poser un Motor6D (C0, C1) dans sa partie Part1 lorsqu'on construit le bras.
			local function motor(name: string, holder, c0: CFrame, c1: CFrame)
				local m = Instance.new("Motor6D")
				m.Name = name
				m.C0 = c0
				m.C1 = c1
				-- Pose de l'Animator serveur (sous Lune, Transform n'a pas de valeur par défaut)
				m.Transform = CFrame.identity
				m.Parent = holder
			end
			motor("Waist", torso, CFrame.new(0, -0.2, 0), LEFT_ARM.waistC1)
			local upperArm = addPart(character, "LeftUpperArm", Vector3.new(-1, 1.1, 0))
			upperArm.Size = LEFT_ARM.upperArmSize
			motor("LeftShoulder", upperArm, CFrame.new(LEFT_ARM.shoulderC0), CFrame.new(LEFT_ARM.shoulderC1))
			local lowerArm = addPart(character, "LeftLowerArm", Vector3.new(-1, 0.1, 0))
			lowerArm.Size = LEFT_ARM.lowerArmSize
			motor("LeftElbow", lowerArm, CFrame.new(LEFT_ARM.elbowC0), CFrame.new(LEFT_ARM.elbowC1))
			local hand = addPart(character, "LeftHand", Vector3.new(-1, -0.6, 0))
			hand.Size = LEFT_ARM.handSize
			motor("LeftWrist", hand, CFrame.new(LEFT_ARM.wristC0), CFrame.new(LEFT_ARM.wristC1))
			return hand, shoulderPos
		end

		T.it(
			"membre (#240) : main vue tenue devant la cible acceptée, silent aim hors de l'allonge refusé",
			function()
				local Validator, a, b, world, ShotRules = setupPose({ direction = "block" })
				local hand, shoulder = addLeftArm(b.Character)
				-- Le tireur voit la main tenue devant la cible (tenue de l'arme posée par les clients), à 2,2 studs de
				-- l'épaule vers lui, quand le rig serveur la montre le long du corps : 3 studs d'écart, refusé avant #240
				local seen = shoulder + Vector3.new(-2.2, 0, 0)
				T.expect(
					(seen - hand.Position).Magnitude > ShotRules.directionLimit(hand.Size.Magnitude / 2, 0),
					"écart"
				)
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, hand, 0, shotAt(a, seen, world.now)), 115)
				T.expectEqual(reportedChecks(world), "", "main tenue")
				-- Silent aim : rayon à côté de la cible, au-delà de l'allonge et de la tolérance
				local radius = ShotRules.limbRadius(LEFT_ARM)
				local aside = shoulder + Vector3.new(0, 0, -(radius + ShotRules.DIRECTION_BASE + 1))
				T.expectEqual(Validator.authorizeHitscan(a, b.Character, hand, 10, shotAt(a, aside, world.now)), nil)
				T.expectEqual(reportedChecks(world), "direction")
				T.expect(
					string.find(world.reports[1].detail, "allonge de l'épaule", 1, true) ~= nil,
					"détail : " .. world.reports[1].detail
				)
			end
		)

		T.it("membre (#240) : tête et main sans rig complet gardent la règle de la partie", function()
			local Validator, a, b, world, ShotRules = setupPose({ direction = "block" })
			local _, shoulder = addLeftArm(b.Character)
			local head = addPart(b.Character, "Head", Vector3.new(0, 2, 0))
			-- Point dans l'allonge de l'épaule mais à 3,5 studs de la tête : refusé pour une touche à la tête
			local nearShoulder = head.Position + Vector3.new(0, 0, 3.5)
			T.expect((nearShoulder - shoulder).Magnitude < 4, "dans l'allonge")
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, head, 0, shotAt(a, nearShoulder, world.now)), nil)
			T.expectEqual(reportedChecks(world), "direction")
			-- Main droite sans bras ni articulations : règle de la partie
			Validator, a, b, world = setupPose({ direction = "block" })
			local rightHand = addPart(b.Character, "RightHand", Vector3.new(0, 0, -2))
			local off = rightHand.Position + Vector3.new(0, 0, -3.5)
			T.expectEqual(Validator.authorizeHitscan(a, b.Character, rightHand, 0, shotAt(a, off, world.now)), nil)
			T.expectEqual(reportedChecks(world), "direction")
			-- Repli : la main droite est bien jugée sur sa propre position, pas dans l'allonge
			T.expect(
				string.find(world.reports[1].detail, "allonge", 1, true) == nil,
				"détail : " .. world.reports[1].detail
			)
			T.expect(ShotRules.limbSide("RightHand") == "Right", "côté")
		end)

		T.it("ne borne pas les tirs des bots par le ping", function()
			local Validator, _, b, world, _, makeBot = setupPose({ ping = "block" })
			world.ping = 0.03
			local bot = makeBot(Vector3.new(50, 0, 0), "AWP")
			T.expectEqual(Validator.authorizeHitscan(bot, b.Character, rootOf(b.Character), 0), 115)
			T.expectEqual(reportedChecks(world), "")
		end)
	end)
end
