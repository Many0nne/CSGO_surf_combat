return function(T, Loader)
	-- Même contexte pour les deux : HUDRules et le test lisent la même instance de KeyBindings
	local loader = Loader.new()
	local HUDRules = loader:require("src/client/ui/HUDRules")
	local KeyBindings = loader:require("src/shared/KeyBindings")

	T.describe("HUDRules.speedTier", function()
		T.it("place chaque vitesse dans le bon palier, seuils inclus", function()
			T.expectEqual(HUDRules.speedTier(0), 1)
			T.expectEqual(HUDRules.speedTier(29.9), 1)
			T.expectEqual(HUDRules.speedTier(30), 2)
			T.expectEqual(HUDRules.speedTier(69), 2)
			T.expectEqual(HUDRules.speedTier(70), 3)
			T.expectEqual(HUDRules.speedTier(120), 4)
			T.expectEqual(HUDRules.speedTier(180), 5)
			T.expectEqual(HUDRules.speedTier(1000), 5)
		end)
	end)

	T.describe("HUDRules.crosshairVisible", function()
		T.it("n'affiche le crosshair que réglage actif, en partie, sans lunette ni Réglages ouverts", function()
			T.expectEqual(HUDRules.crosshairVisible(true, true, false, false), true)
			T.expectEqual(HUDRules.crosshairVisible(false, true, false, false), false, "réglage coupé")
			T.expectEqual(HUDRules.crosshairVisible(true, false, false, false), false, "HUD masqué")
			T.expectEqual(HUDRules.crosshairVisible(true, true, true, false), false, "lunette")
			T.expectEqual(HUDRules.crosshairVisible(true, true, false, true), false, "Réglages ouverts")
		end)
	end)

	T.describe("HUDRules.keyDisplayEntries", function()
		local function ids(mode: string): string
			local list = {}
			for _, entry in HUDRules.keyDisplayEntries(mode) do
				table.insert(list, entry.id)
			end
			return table.concat(list, ",")
		end

		T.it("n'a aucune touche désactivé ou pour un mode inconnu", function()
			T.expectEqual(ids("off"), "")
			T.expectEqual(ids("nimporte"), "")
		end)

		T.it("simple : les quatre directions et le saut, sans accroupi ni actions", function()
			T.expectEqual(ids("simple"), "forward,left,back,right,jump")
		end)

		T.it("complet : simple plus accroupi, marche lente, tir, visée, recharge et inspection, sans armes", function()
			T.expectEqual(ids("full"), "forward,left,back,right,jump,fire,aim,reload,inspect,crouch,walk")
		end)

		T.it("place chaque touche sur une case libre de la grille", function()
			for _, mode in { "simple", "full" } do
				local taken = {}
				for _, entry in HUDRules.keyDisplayEntries(mode) do
					for col = entry.col, entry.col + entry.width - 1 do
						local cell = col .. ":" .. entry.row
						T.expectEqual(
							taken[cell],
							nil,
							mode .. " " .. entry.id .. " chevauche " .. tostring(taken[cell])
						)
						taken[cell] = entry.id
					end
				end
			end
		end)

		T.it("lie chaque touche à un clavier ou à un bouton de souris", function()
			for _, entry in HUDRules.keyDisplayEntries("full") do
				T.expectEqual(entry.keys ~= nil or entry.mouse ~= nil, true, entry.id)
			end
		end)

		T.it("tire chaque action affichée des liaisons d'InputModule (KeyBindings, #224)", function()
			local keyMap = KeyBindings.keyMap()
			for _, entry in HUDRules.keyDisplayEntries("full") do
				if entry.mouse then
					T.expectEqual(entry.mouse, KeyBindings.MOUSE[entry.id], entry.id)
				else
					T.expectEqual(entry.keys, KeyBindings.KEYS[entry.id], entry.id)
					for _, key in entry.keys or {} do
						T.expectEqual(keyMap[key], entry.id, entry.id .. " " .. key)
					end
				end
			end
		end)
	end)

	T.describe("HUDRules.keyDisplayVisible", function()
		T.it("n'affiche les touches que mode actif, en partie, Réglages fermés", function()
			T.expectEqual(HUDRules.keyDisplayVisible("simple", true, false), true)
			T.expectEqual(HUDRules.keyDisplayVisible("full", true, false), true)
			T.expectEqual(HUDRules.keyDisplayVisible("off", true, false), false, "réglage coupé")
			T.expectEqual(HUDRules.keyDisplayVisible("simple", false, false), false, "HUD masqué")
			T.expectEqual(HUDRules.keyDisplayVisible("full", true, true), false, "Réglages ouverts")
		end)
	end)

	T.describe("HUDRules.gameHudVisible", function()
		T.it("n'affiche le HUD de jeu qu'en partie avec un personnage vivant", function()
			T.expectEqual(HUDRules.gameHudVisible("IN_ROUND"), true)
			for _, state in { "MENU", "INFOS", "SPAWNING", "DEAD", "RESULT" } do
				T.expectEqual(HUDRules.gameHudVisible(state), false)
			end
		end)
	end)

	T.describe("HUDRules.killFeedVisible", function()
		T.it("affiche le kill feed en partie, vivant ou mort", function()
			T.expectEqual(HUDRules.killFeedVisible("IN_ROUND"), true)
			T.expectEqual(HUDRules.killFeedVisible("DEAD"), true)
			for _, state in { "MENU", "INFOS", "SPAWNING", "RESULT" } do
				T.expectEqual(HUDRules.killFeedVisible(state), false)
			end
		end)
	end)

	T.describe("HUDRules.killDetail", function()
		T.it("donne l'arme, la tête si tir à la tête, et CHUTE sans tueur", function()
			T.expectEqual(HUDRules.killDetail("Kev", "AWP", false), "AWP")
			T.expectEqual(HUDRules.killDetail("Kev", "AWP", true), "AWP · TÊTE")
			T.expectEqual(HUDRules.killDetail("Kev", "M9Bayonet", false), "M9 BAYONET")
			T.expectEqual(HUDRules.killDetail("Kev", nil, true), "TÊTE")
			T.expectEqual(HUDRules.killDetail(nil, "AWP", true), "CHUTE")
		end)
	end)

	T.describe("HUDRules.pushKillFeed / pruneKillFeed", function()
		local function entry(victim: string, at: number)
			return { killer = "Kev", victim = victim, weapon = "AWP", headshot = false, mine = false, at = at }
		end

		T.it("met la mort la plus récente en premier et garde KILL_FEED_MAX lignes", function()
			local feed = {}
			for i = 1, HUDRules.KILL_FEED_MAX + 2 do
				feed = HUDRules.pushKillFeed(feed, entry("V" .. i, i * 0.1), i * 0.1)
			end
			T.expectEqual(#feed, HUDRules.KILL_FEED_MAX)
			T.expectEqual(feed[1].victim, "V" .. (HUDRules.KILL_FEED_MAX + 2))
			T.expectEqual(feed[HUDRules.KILL_FEED_MAX].victim, "V3")
		end)

		T.it("retire les lignes affichées depuis KILL_FEED_DURATION", function()
			local feed = { entry("Récent", 10), entry("Ancien", 10 - HUDRules.KILL_FEED_DURATION) }
			local kept = HUDRules.pruneKillFeed(feed, 10)
			T.expectEqual(#kept, 1)
			T.expectEqual(kept[1].victim, "Récent")
			T.expectEqual(#HUDRules.pushKillFeed(feed, entry("Neuf", 10), 10), 2)
		end)
	end)

	T.describe("HUDRules.acceptsRoundResult", function()
		T.it("n'accepte le résultat de round qu'en partie (vivant ou mort)", function()
			T.expectEqual(HUDRules.acceptsRoundResult("IN_ROUND"), true)
			T.expectEqual(HUDRules.acceptsRoundResult("DEAD"), true)
			for _, state in { "MENU", "INFOS", "SPAWNING", "RESULT" } do
				T.expectEqual(HUDRules.acceptsRoundResult(state), false)
			end
		end)
	end)

	T.describe("HUDRules.speedFill", function()
		T.it("remplit la ligne proportionnellement, pleine au dernier palier, bornée à 0 et 1", function()
			T.expectEqual(HUDRules.speedFill(0), 0)
			T.expectEqual(HUDRules.speedFill(90), 0.5)
			T.expectEqual(HUDRules.speedFill(180), 1)
			T.expectEqual(HUDRules.speedFill(1000), 1)
			T.expectEqual(HUDRules.speedFill(-5), 0)
		end)
	end)

	T.describe("HUDRules.formatTimer", function()
		T.it("formate en m:ss et borne à zéro", function()
			T.expectEqual(HUDRules.formatTimer(300), "5:00")
			T.expectEqual(HUDRules.formatTimer(65), "1:05")
			T.expectEqual(HUDRules.formatTimer(9.7), "0:09")
			T.expectEqual(HUDRules.formatTimer(-3), "0:00")
		end)

		T.it("passe en alerte à 30 s et moins", function()
			T.expectEqual(HUDRules.isLowTime(31), false)
			T.expectEqual(HUDRules.isLowTime(30), true)
		end)
	end)

	T.describe("HUDRules.sortScores / rankOf", function()
		local scores = {
			[1] = { name = "manyonne", kills = 0, deaths = 3 },
			[2] = { name = "Specter", kills = 3, deaths = 2 },
			[3] = { name = "Ramsey", kills = 3, deaths = 1 },
			[4] = { name = "Volkov", kills = 3, deaths = 2 },
		}

		T.it("trie par kills, puis morts, puis nom", function()
			local sorted = HUDRules.sortScores(scores)
			T.expectEqual(sorted[1].name, "Ramsey")
			T.expectEqual(sorted[2].name, "Specter")
			T.expectEqual(sorted[3].name, "Volkov")
			T.expectEqual(sorted[4].name, "manyonne")
		end)

		T.it("retrouve le rang du joueur local, nil s'il est absent", function()
			local sorted = HUDRules.sortScores(scores)
			T.expectEqual(HUDRules.rankOf(sorted, "manyonne"), 4)
			T.expectEqual(HUDRules.rankOf(sorted, "Inconnu"), nil)
		end)
	end)

	T.describe("HUDRules.formatKD / secondsLeft", function()
		T.it("calcule le K/D sans division par zéro", function()
			T.expectEqual(HUDRules.formatKD(3, 2), "1.50")
			T.expectEqual(HUDRules.formatKD(1, 0), "1.00")
			T.expectEqual(HUDRules.formatKD(0, 3), "0.00")
		end)

		T.it("arrondit le compte à rebours à la seconde supérieure", function()
			T.expectEqual(HUDRules.secondsLeft(12.5, 10), 3)
			T.expectEqual(HUDRules.secondsLeft(12, 10), 2)
			T.expectEqual(HUDRules.secondsLeft(10, 12), 0)
		end)
	end)

	T.describe("HUDRules.cycleSlot", function()
		T.it("passe à l'emplacement voisin en bouclant dans les deux sens", function()
			T.expectEqual(HUDRules.cycleSlot(1, 3, 1), 2)
			T.expectEqual(HUDRules.cycleSlot(3, 3, 1), 1)
			T.expectEqual(HUDRules.cycleSlot(1, 3, -1), 3)
			T.expectEqual(HUDRules.cycleSlot(2, 2, -1), 1)
		end)

		T.it("part d'un bout sans arme en main, et ne renvoie rien sans arme", function()
			T.expectEqual(HUDRules.cycleSlot(nil, 3, 1), 1)
			T.expectEqual(HUDRules.cycleSlot(nil, 3, -1), 3)
			T.expectEqual(HUDRules.cycleSlot(nil, 0, 1), nil)
			T.expectEqual(HUDRules.cycleSlot(1, 0, -1), nil)
		end)
	end)

	T.describe("HUDRules.weaponLabel", function()
		T.it("sépare les mots collés et passe en majuscules", function()
			T.expectEqual(HUDRules.weaponLabel("M9Bayonet"), "M9 BAYONET")
			T.expectEqual(HUDRules.weaponLabel("AWP"), "AWP")
			T.expectEqual(HUDRules.weaponLabel("DesertEagle"), "DESERT EAGLE")
		end)
	end)

	T.describe("HUDRules.formatReserve (#165)", function()
		T.it("affiche ∞ pour une réserve illimitée et le nombre sinon", function()
			T.expectEqual(HUDRules.formatReserve(math.huge), "/ ∞")
			T.expectEqual(HUDRules.formatReserve(10), "/ 10")
			T.expectEqual(HUDRules.formatReserve(0), "/ 0")
		end)
	end)

	T.describe("HUDRules.slotOrder", function()
		T.it("trie par ordre alphabétique sans modifier la liste reçue", function()
			local names = { "M9Bayonet", "AWP" }
			local sorted = HUDRules.slotOrder(names)
			T.expectEqual(sorted[1], "AWP")
			T.expectEqual(sorted[2], "M9Bayonet")
			T.expectEqual(names[1], "M9Bayonet")
		end)
	end)

	T.describe("HUDRules : annonce de mort (#137)", function()
		T.it("lit les noms et drapeaux bot sans Player", function()
			local death = HUDRules.readDeath({
				victimId = 7,
				victimName = "Alice",
				victimIsBot = false,
				killerId = -1,
				killerName = "Marcel",
				killerIsBot = true,
				weapon = "AWP",
				headshot = true,
			}, 7)
			T.expectEqual(death.victim, "Alice")
			T.expectEqual(death.killer, "Marcel")
			T.expectEqual(death.killerIsBot, true)
			T.expectEqual(death.victimIsBot, false)
			T.expectEqual(death.mine, true, "le joueur local est la victime")
		end)

		T.it("reconnaît le joueur local tueur d'un bot", function()
			local death = HUDRules.readDeath(
				{ victimId = -2, victimName = "Lucie", victimIsBot = true, killerId = 7, killerName = "Alice" },
				7
			)
			T.expectEqual(death.mine, true)
			T.expectEqual(death.victimIsBot, true)
			T.expectEqual(death.killerIsBot, false)
		end)

		T.it("traite une mort sans tueur comme une chute", function()
			local death = HUDRules.readDeath({ victimId = -2, victimName = "Lucie", victimIsBot = true }, 7)
			T.expectEqual(death.killer, nil)
			T.expectEqual(death.killerId, nil)
			T.expectEqual(death.mine, false)
			T.expectEqual(HUDRules.killDetail(death.killer, death.weapon, death.headshot), "CHUTE")
		end)

		T.it("refuse une annonce mal formée", function()
			T.expectEqual(HUDRules.readDeath(nil, 7), nil)
			T.expectEqual(HUDRules.readDeath({ victimId = 7 }, 7), nil, "sans nom de victime")
		end)

		T.it("ne prend pas un bot homonyme pour le joueur local au classement", function()
			local sorted = {
				{ name = "Alice", isBot = true, kills = 3, deaths = 0 },
				{ name = "Alice", isBot = false, kills = 1, deaths = 0 },
			}
			T.expectEqual(HUDRules.rankOf(sorted, "Alice"), 2)
		end)

		T.it("échappe un nom pour le RichText", function()
			T.expectEqual(HUDRules.escapeRichText("<a&b>"), "&lt;a&amp;b&gt;")
		end)
	end)
end
