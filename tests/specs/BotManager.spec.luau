-- Retrait d'un bot (#218) : BotManager sort le bot du classement et du registre, et oublie son état de combat
-- (Validator, relais des tirs). Le cerveau, les armes, le mouvement et le plan de navigation sont simulés : seule la
-- gestion de la liste des bots est testée ici.
return function(T, Loader)
	-- Cette méthode permet de monter un BotManager neuf lorsqu'un test retire des bots : services, `task` et modules de
	-- bots simulés, vrais Participants, Validator et ShotRelayRules. `forgetCalls` compte les oublis demandés.
	local function setup()
		local Players = {
			GetPlayerFromCharacter = function()
				return nil
			end,
			GetPlayers = function()
				return {}
			end,
		}
		local RunService = {
			Heartbeat = {
				Connect = function() end,
			},
			IsStudio = function()
				return false
			end,
		}
		local stubs = {
			BotArsenal = {},
			BotBrain = { stats = { hits = 0, kills = 0 } },
			BotMotion = {},
			NavDebug = { init = function() end },
			NavPlan = { start = function() end },
		}
		local scriptStub = { Parent = {} }
		for name, stub in stubs do
			scriptStub.Parent[name] = { __stub = stub }
		end
		local loader
		-- Services demandés au chargement par les modules de bots (rien n'y est appelé tant que le test ne fait pas
		-- apparaître de personnage)
		loader = Loader.new({
			Players = Players,
			RunService = RunService,
			StarterPack = {},
			StarterPlayer = {},
			CollectionService = {},
		}, {
			script = scriptStub,
			-- Aucune boucle ni attente ne démarre : le test pilote add / removeAt lui-même
			task = { spawn = function() end, wait = function() end, delay = function() end },
			require = function(target)
				-- rawget : un nœud de chemin du Loader répond à n'importe quelle clé
				local stub = if type(target) == "table" then rawget(target, "__stub") else nil
				if stub then
					return stub
				end
				return loader:require(target)
			end,
		})
		local env = {
			BotManager = loader:require("src/server/bots/BotManager"),
			Participants = loader:require("src/server/Participants"),
			Validator = loader:require("src/server/Validator"),
			ShotRelayRules = loader:require("src/server/ShotRelayRules"),
			removedFromRound = {},
			addedToRound = {},
			forgetCalls = 0,
		}
		env.shotRelay = env.ShotRelayRules.new()
		env.BotManager.init({
			onCharacter = function() end,
			place = function() end,
			relay = function() end,
			hitscan = function() end,
			melee = function() end,
			shotFired = function()
				return true
			end,
			-- Même oubli que forgetCombatState de init.server
			forget = function(participant)
				env.forgetCalls += 1
				env.Validator.forget(participant)
				env.ShotRelayRules.forget(env.shotRelay, participant)
			end,
			roundManager = {
				isActive = function()
					return false
				end,
				addParticipant = function(participant)
					table.insert(env.addedToRound, participant)
				end,
				removeParticipant = function(participant)
					table.insert(env.removedFromRound, participant)
				end,
			},
		})
		return env
	end

	-- Cette méthode permet de construire un personnage minimal (racine posée + humanoïde) lorsqu'un test fait frapper un
	-- bot ; cible : le helper de playtest l'accepte sans participant (DEBUG_TARGET_ATTRIBUTE).
	local function makeCharacter(position: Vector3)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = position
		root.CFrame = CFrame.new(position)
		root.Parent = model
		-- Lune n'a pas de Health par défaut : posée, la cible est vivante
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = model
		return model
	end

	-- Cette méthode permet de donner de l'état de combat à un bot lorsqu'un test simule ses attaques, par le chemin de
	-- production : un coup de couteau accepté par le Validator (cadence, `lastAttacks` : le seul état d'un bot, ses
	-- equip et chargeur étant exclus), puis un tir relayé (cadence du relais des tirs).
	local function giveCombatState(env, participant)
		local char = makeCharacter(Vector3.zero)
		local knife = Instance.new("Tool")
		knife.Name = "M9Bayonet"
		knife.Parent = char
		env.Participants.setCharacter(participant, char)
		local target = makeCharacter(Vector3.new(3, 0, 0))
		target:SetAttribute(env.Validator.DEBUG_TARGET_ATTRIBUTE, true)
		T.expect(env.Validator.authorizeMelee(participant, target, "primary", 10), "le coup du bot doit être accepté")
		local admitted = env.ShotRelayRules.admit(
			env.shotRelay,
			participant,
			"AWP",
			Vector3.new(0, 2, 0),
			Vector3.new(0, 0, -1),
			Vector3.zero,
			10
		)
		T.expect(admitted, "le tir du bot doit être relayé pour que le test ait un état à oublier")
	end

	T.describe("BotManager.removeAt (#218)", function()
		T.it("efface l'état du Validator et du relais d'un bot retiré", function()
			local env = setup()
			local bot = env.BotManager.add() :: any
			giveCombatState(env, bot)
			T.expectEqual(env.Validator.hasEntries(bot), true, "état avant le retrait")
			T.expect(env.shotRelay.last[bot] ~= nil, "relais avant le retrait")

			env.BotManager.removeAt()

			T.expectEqual(env.Validator.hasEntries(bot), false, "Validator après le retrait")
			T.expectEqual(env.shotRelay.last[bot], nil, "relais après le retrait")
			T.expectEqual(env.Validator.trackedCount(), 0, "aucun participant suivi")
		end)

		T.it("ne touche pas à l'état des autres participants", function()
			local env = setup()
			local first = env.BotManager.add() :: any
			local second = env.BotManager.add() :: any
			giveCombatState(env, first)
			giveCombatState(env, second)

			env.BotManager.removeAt(2)

			T.expectEqual(env.Validator.hasEntries(second), false, "bot retiré oublié")
			T.expectEqual(env.Validator.hasEntries(first), true, "bot resté en jeu gardé")
			T.expect(env.shotRelay.last[first] ~= nil, "relais du bot resté gardé")
			T.expectEqual(env.Validator.trackedCount(), 1)
		end)

		T.it("le va-et-vient de bots ne laisse aucune entrée", function()
			local env = setup()
			for _ = 1, 20 do
				local bot = env.BotManager.add() :: any
				giveCombatState(env, bot)
				env.BotManager.removeAt()
			end
			T.expectEqual(env.Validator.trackedCount(), 0)
			T.expectEqual(next(env.shotRelay.last), nil, "relais vide")
			T.expectEqual(env.BotManager.count(), 0)
		end)

		T.it("sort aussi le bot du classement et du registre, et oublie une fois par retrait", function()
			local env = setup()
			local bot = env.BotManager.add() :: any
			env.BotManager.removeAt()
			T.expectEqual(env.removedFromRound[1], bot, "retiré du classement")
			T.expectEqual(env.Participants.isRegistered(bot), false, "désinscrit du registre")
			T.expectEqual(env.forgetCalls, 1)
		end)

		T.it("retirer quand il n'y a plus de bot ne fait rien", function()
			local env = setup()
			env.BotManager.removeAt()
			T.expectEqual(env.forgetCalls, 0)
		end)
	end)

	T.describe("Validator.hasEntries et trackedCount", function()
		T.it("suivent la cadence d'un bot et retombent à zéro au forget", function()
			local env = setup()
			local bot = env.BotManager.add() :: any
			T.expectEqual(env.Validator.hasEntries(bot), false, "rien au départ")
			T.expectEqual(env.Validator.trackedCount(), 0)
			giveCombatState(env, bot)
			T.expectEqual(env.Validator.hasEntries(bot), true)
			T.expectEqual(env.Validator.trackedCount(), 1)
			env.Validator.forget(bot)
			T.expectEqual(env.Validator.hasEntries(bot), false)
			T.expectEqual(env.Validator.trackedCount(), 0)
		end)

		T.it("suivent aussi l'equip d'un joueur, compté une seule fois avec sa cadence", function()
			local env = setup()
			local player = { id = 7, name = "Alice", isBot = false } :: any
			env.Validator.noteEquip(player, Instance.new("Tool"), 1)
			T.expectEqual(env.Validator.hasEntries(player), true, "equip")
			T.expectEqual(env.Validator.trackedCount(), 1)
			env.Validator.forget(player)
			T.expectEqual(env.Validator.hasEntries(player), false)
			T.expectEqual(env.Validator.trackedCount(), 0)
		end)
	end)
end
