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

	-- Cette méthode permet de composer un état du HUD (HUDState) lorsqu'un test de visibilité en a besoin : en partie,
	-- menu fermé, sans lunette, sauf champs donnés.
	local function hud(fields: { [string]: any }?): HUDRules.HUDSnapshot
		local result = { gameState = "IN_ROUND", menuOpen = false, scoped = false }
		for key, value in fields or {} do
			(result :: any)[key] = value
		end
		return result
	end

	T.describe("HUDRules.crosshairVisible", function()
		T.it("n'affiche le crosshair que réglage actif, en partie, sans lunette ni menu ouvert", function()
			T.expectEqual(HUDRules.crosshairVisible(hud(), true), true)
			T.expectEqual(HUDRules.crosshairVisible(hud(), false), false, "réglage coupé")
			T.expectEqual(HUDRules.crosshairVisible(hud({ scoped = true }), true), false, "lunette")
			T.expectEqual(HUDRules.crosshairVisible(hud({ menuOpen = true }), true), false, "menu en partie ouvert")
		end)

		T.it("masque le crosshair hors partie : mort, menu principal, réapparition, résultat", function()
			for _, state in { "DEAD", "MENU", "INFOS", "SPAWNING", "RESULT" } do
				T.expectEqual(HUDRules.crosshairVisible(hud({ gameState = state }), true), false, state)
			end
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
		T.it("n'affiche les touches que mode actif, en partie, menu fermé", function()
			T.expectEqual(HUDRules.keyDisplayVisible(hud(), "simple"), true)
			T.expectEqual(HUDRules.keyDisplayVisible(hud(), "full"), true)
			T.expectEqual(HUDRules.keyDisplayVisible(hud(), "off"), false, "réglage coupé")
			T.expectEqual(HUDRules.keyDisplayVisible(hud({ menuOpen = true }), "full"), false, "menu en partie ouvert")
		end)

		T.it("garde les touches en lunette, les masque hors partie (mort comprise)", function()
			T.expectEqual(HUDRules.keyDisplayVisible(hud({ scoped = true }), "simple"), true, "lunette")
			for _, state in { "DEAD", "MENU", "INFOS", "SPAWNING", "RESULT" } do
				T.expectEqual(HUDRules.keyDisplayVisible(hud({ gameState = state }), "simple"), false, state)
			end
		end)
	end)

	T.describe("HUDRules.keyDisplayMode (#291)", function()
		T.it("affiche le mode complet à un débutant, quel que soit son réglage", function()
			for _, setting in { "off", "simple", "full" } do
				T.expectEqual(HUDRules.keyDisplayMode(setting, true), "full", setting)
			end
			T.expectEqual(HUDRules.keyDisplayVisible(hud(), HUDRules.keyDisplayMode("off", true)), true)
		end)

		T.it("rend son réglage au joueur qui n'est plus débutant", function()
			for _, setting in { "off", "simple", "full" } do
				T.expectEqual(HUDRules.keyDisplayMode(setting, false), setting, setting)
			end
		end)
	end)

	T.describe("HUDRules.keyDisplayGridSize", function()
		T.it("mesure la grille : 3 colonnes en simple, 6 en full, 3 rangées, rien en off", function()
			local w, h = HUDRules.keyDisplayGridSize("simple")
			T.expectEqual(w, 3 * 44 - 4)
			T.expectEqual(h, 3 * 44 - 4)
			T.expectEqual((HUDRules.keyDisplayGridSize("full")), 6 * 44 - 4)
			T.expectEqual((HUDRules.keyDisplayGridSize("off")), 0)
		end)
	end)

	T.describe("HUDRules.keyDisplayBottom", function()
		-- Cette méthode permet de lire la largeur de la grille (px) d'un mode lorsqu'un test la place, telle que KeyDisplay la construit.
		local function gridWidth(mode: string): number
			return (HUDRules.keyDisplayGridSize(mode))
		end

		local lifted = HUDRules.AMMO_BOX.bottom + HUDRules.AMMO_BOX.height + HUDRules.KEY_DISPLAY_CLEARANCE

		T.it("garde la grille en bas en 16:9 et plus large, mode full compris", function()
			for _, width in { 1280, 1531, 1680 } do -- 16:9, fenêtre Studio 1291x607, 21:9
				T.expectEqual(
					HUDRules.keyDisplayBottom(width, gridWidth("full")),
					HUDRules.KEY_DISPLAY_BOTTOM,
					tostring(width)
				)
				T.expectEqual(
					HUDRules.keyDisplayBottom(width, gridWidth("simple")),
					HUDRules.KEY_DISPLAY_BOTTOM,
					tostring(width)
				)
			end
		end)

		T.it("remonte la grille full au-dessus des munitions en 4:3 et 16:10", function()
			T.expectEqual(HUDRules.keyDisplayBottom(960, gridWidth("full")), lifted, "4:3")
			T.expectEqual(HUDRules.keyDisplayBottom(1152, gridWidth("full")), lifted, "16:10")
			T.expectEqual(lifted > HUDRules.AMMO_BOX.bottom + HUDRules.AMMO_BOX.height, true, "au-dessus du compteur")
		end)

		T.it("ne remonte la grille simple que si elle atteint les munitions (16:10 non, 4:3 oui)", function()
			T.expectEqual(HUDRules.keyDisplayBottom(1152, gridWidth("simple")), HUDRules.KEY_DISPLAY_BOTTOM, "16:10")
			T.expectEqual(HUDRules.keyDisplayBottom(960, gridWidth("simple")), lifted, "4:3")
		end)

		T.it("bascule au seuil exact de l'écart minimal", function()
			local grid = gridWidth("full")
			-- gridRight + clearance = ammoLeft  <=>  width = grid + 2 * (right + width + clearance)
			local box = HUDRules.AMMO_BOX
			local threshold = grid + 2 * (box.right + box.width + HUDRules.KEY_DISPLAY_CLEARANCE)
			T.expectEqual(HUDRules.keyDisplayBottom(threshold, grid), HUDRules.KEY_DISPLAY_BOTTOM, "au seuil")
			T.expectEqual(HUDRules.keyDisplayBottom(threshold - 1, grid), lifted, "sous le seuil")
		end)
	end)

	T.describe("HUDRules.roundTimerOverMenu", function()
		T.it("passe le timer au-dessus du menu en partie ouvert, vivant ou mort, lunette ou non", function()
			T.expectEqual(HUDRules.roundTimerOverMenu(hud({ menuOpen = true })), true)
			T.expectEqual(HUDRules.roundTimerOverMenu(hud({ menuOpen = true, gameState = "DEAD" })), true, "mort")
			T.expectEqual(HUDRules.roundTimerOverMenu(hud({ menuOpen = true, scoped = true })), true, "lunette")
		end)

		T.it("laisse le timer dans le HUD menu fermé", function()
			T.expectEqual(HUDRules.roundTimerOverMenu(hud()), false)
			T.expectEqual(HUDRules.roundTimerOverMenu(hud({ gameState = "DEAD" })), false, "mort")
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
		T.it("range SNIPER puis COUTEAU (#280) sans modifier la liste reçue", function()
			local names = { "M9Bayonet", "AWP" }
			local sorted = HUDRules.slotOrder(names)
			T.expectEqual(sorted[1], "AWP")
			T.expectEqual(sorted[2], "M9Bayonet")
			T.expectEqual(names[1], "M9Bayonet")
		end)

		T.it("un outil hors catalogue passe après les emplacements, même s'il précède dans l'alphabet", function()
			T.expectEqual(table.concat(HUDRules.slotOrder({ "Inconnu", "KaBar", "AWP" }), ","), "AWP,KaBar,Inconnu")
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

	T.describe("HUDRules : fiche de statistiques de l'accueil (#301)", function()
		T.it("vue non chargée : « — » partout, ratio compris", function()
			local view = HUDRules.statsView(nil)
			for _, key in { "kills", "deaths", "ratio", "roundsPlayed", "roundsWon" } do
				T.expectEqual(view[key], HUDRules.STATS_UNKNOWN, key)
			end
			T.expectEqual(HUDRules.STATS_UNKNOWN, "—")
		end)

		T.it("ratio : deux décimales comme le classement, sans mort il vaut les kills", function()
			T.expectEqual(HUDRules.statsRatio(0, 0), "0.00")
			T.expectEqual(HUDRules.statsRatio(7, 0), "7.00")
			T.expectEqual(HUDRules.statsRatio(3, 2), "1.50")
			T.expectEqual(HUDRules.statsRatio(2, 3), "0.67")
			T.expectEqual(HUDRules.statsRatio(250, 0), "250", "à partir de 100, sans décimale")
			T.expectEqual(
				HUDRules.statsRatio(19999, 200),
				"100",
				"99.995 arrondi à 100 : sans décimale, pas « 100.00 »"
			)
			T.expectEqual(HUDRules.statsRatio(19899, 200), "99.50", "même arrondi que le classement")
			T.expectEqual(HUDRules.statsRatio(3, 2), HUDRules.formatKD(3, 2), "identique au classement sous 100")
			T.expectEqual(HUDRules.statsRatio(25000, 0), "25.0k")
		end)

		T.it("grands nombres : chiffres complets sous 10 000, puis k et M tronqués", function()
			T.expectEqual(HUDRules.formatCount(0), "0")
			T.expectEqual(HUDRules.formatCount(999), "999")
			T.expectEqual(HUDRules.formatCount(1000), "1 000")
			T.expectEqual(HUDRules.formatCount(9999), "9 999")
			T.expectEqual(HUDRules.formatCount(10000), "10.0k")
			T.expectEqual(HUDRules.formatCount(12345), "12.3k")
			T.expectEqual(HUDRules.formatCount(99999), "99.9k", "tronqué : jamais 100.0k")
			T.expectEqual(HUDRules.formatCount(123456), "123k")
			T.expectEqual(HUDRules.formatCount(999999), "999k")
			T.expectEqual(HUDRules.formatCount(1000000), "1.0M")
			T.expectEqual(HUDRules.formatCount(1250000), "1.2M")
			T.expectEqual(HUDRules.formatCount(123456789), "123M")
		end)

		T.it("vue chargée : compteurs mis en forme", function()
			local view = HUDRules.statsView({ kills = 12345, deaths = 0, roundsPlayed = 40, roundsWon = 9 })
			T.expectEqual(view.kills, "12.3k")
			T.expectEqual(view.deaths, "0")
			T.expectEqual(view.ratio, "12.3k")
			T.expectEqual(view.roundsPlayed, "40")
			T.expectEqual(view.roundsWon, "9")
		end)
	end)

	T.describe("HUDRules.readRoundResult (#295)", function()
		local ME = 42
		-- Cette méthode permet de composer un score envoyé par RoundResult lorsqu'un test décrit une fin de manche.
		local function entry(id: number, name: string, kills: number, deaths: number, isBot: boolean?)
			return { id = id, name = name, isBot = isBot == true, kills = kills, deaths = deaths }
		end
		local scores = {
			entry(1, "Ramsey", 3, 1),
			entry(-1, "Marcel", 5, 2, true),
			entry(ME, "manyonne", 0, 3),
			entry(2, "Specter", 3, 2),
			entry(3, "Volkov", 1, 0),
		}

		-- Cette méthode permet de lister les noms des lignes du podium lorsqu'un test vérifie leur ordre.
		local function podiumNames(view): string
			local names = {}
			for _, row in view.podium do
				table.insert(names, row.rank .. ":" .. row.score.name)
			end
			return table.concat(names, ",")
		end

		T.it("montre les trois premiers dans l'ordre du classement et la ligne du joueur hors podium", function()
			local view = HUDRules.readRoundResult({ outcome = "winner", winnerId = -1, scores = scores }, ME)
			T.expectEqual(podiumNames(view), "1:Marcel,2:Ramsey,3:Specter")
			T.expect(view.me ~= nil, "joueur hors podium")
			T.expectEqual(view.me and view.me.rank, 5)
			T.expectEqual(view.me and view.me.score.kills, 0)
			T.expectEqual(view.me and view.me.score.deaths, 3)
		end)

		T.it("même ordre que le classement de Tab", function()
			local sorted = HUDRules.sortScores(scores)
			local view = HUDRules.readRoundResult({ outcome = "none", scores = scores }, ME)
			for i, row in view.podium do
				T.expectEqual(row.score.id, sorted[i].id)
			end
		end)

		T.it("résout le nom d'un bot vainqueur par son id, avec le préfixe", function()
			local view = HUDRules.readRoundResult({ outcome = "winner", winnerId = -1, scores = scores }, ME)
			T.expectEqual(view.title, "BOT MARCEL")
			T.expectEqual(view.hasWinner, true)
			T.expectEqual(view.subtitle, "REMPORTE LE ROUND")
			T.expectEqual(view.meWins, false)
		end)

		T.it("signale la victoire du joueur local, sans ligne en double", function()
			local mine = { entry(ME, "manyonne", 4, 0), entry(-1, "manyonne", 1, 1, true) }
			local view = HUDRules.readRoundResult({ outcome = "winner", winnerId = ME, scores = mine }, ME)
			T.expectEqual(view.title, "MANYONNE")
			T.expectEqual(view.subtitle, "TU REMPORTES LE ROUND")
			T.expectEqual(view.meWins, true)
			T.expectEqual(view.podium[1].isMe, true)
			T.expectEqual(view.podium[2].isMe, false, "bot homonyme")
			T.expectEqual(view.me, nil, "déjà sur le podium")
		end)

		T.it("affiche ÉGALITÉ ou AUCUN VAINQUEUR sans sous-titre", function()
			local tie = HUDRules.readRoundResult({ outcome = "tie", scores = scores }, ME)
			T.expectEqual(tie.title, "ÉGALITÉ")
			T.expectEqual(tie.subtitle, "")
			T.expectEqual(tie.meWins, false)
			T.expectEqual(tie.hasWinner, false, "premier du podium pas mis en avant")
			local none = HUDRules.readRoundResult({ outcome = "none", scores = scores }, ME)
			T.expectEqual(none.title, "AUCUN VAINQUEUR")
			T.expectEqual(none.subtitle, "")
			T.expectEqual(none.hasWinner, false)
		end)

		T.it("ne montre pas de ligne pour un joueur absent de la manche", function()
			local view = HUDRules.readRoundResult({ outcome = "winner", winnerId = 1, scores = scores }, 999)
			T.expectEqual(view.me, nil)
			T.expectEqual(#view.podium, 3)
		end)

		T.it("ignore un vainqueur absent des scores et les entrées mal formées", function()
			local view = HUDRules.readRoundResult({
				outcome = "winner",
				winnerId = 7,
				scores = { entry(1, "Ramsey", 1, 0), { name = "sans id", kills = 1, deaths = 0 }, "x" },
			}, ME)
			T.expectEqual(view.title, "AUCUN VAINQUEUR")
			T.expectEqual(#view.podium, 1)
			local empty = HUDRules.readRoundResult(nil, ME)
			T.expectEqual(empty.title, "AUCUN VAINQUEUR")
			T.expectEqual(#empty.podium, 0)
		end)
	end)
end
