-- Journal des violations (#170) : compteurs, score décroissant, warn limité, kick à 3 violations fortes, bots et
-- Studio sans sanction, résumé au départ, garde des remotes branchée sur le journal. Mesure (#297) : compteurs par
-- contrôle, dénominateurs, ping, relevé agrégé, nouvel essai du webhook puis repli console.
return function(T, Loader)
	-- Cette méthode permet de monter un CheatLog neuf avec horloge, console, Studio, webhook et `task` simulés lorsqu'un
	-- test démarre ; spawned garde les envois lancés (résumés, relevés) sans les exécuter, webhooks donne les URL
	-- configurées par nom de StringValue, failPosts le nombre de PostAsync qui échouent avant le premier qui passe.
	local function setup(isStudio: boolean?)
		local env = {
			clock = 0,
			warns = {},
			prints = {},
			spawned = {},
			waits = {},
			webhooks = {} :: { [string]: string },
			posts = 0,
			failPosts = 0,
			postError = "HTTP 429 (Too Many Requests)",
			players = {},
		}
		local realServerScripts = Loader.new().game:GetService("ServerScriptService")
		local loader = Loader.new({
			Players = {
				PlayerRemoving = {
					Connect = function() end,
				},
				GetPlayers = function()
					return env.players
				end,
			},
			RunService = {
				IsStudio = function()
					return isStudio == true
				end,
			},
			-- Arborescence Rojo réelle, plus les StringValue des webhooks (Webhook.url)
			ServerScriptService = {
				Server = realServerScripts.Server,
				FindFirstChild = function(_, name)
					local url = env.webhooks[name]
					if not url then
						return nil
					end
					return {
						Value = url,
						IsA = function(_, className)
							return className == "StringValue"
						end,
					}
				end,
			},
			HttpService = {
				JSONEncode = function()
					return "{}"
				end,
				PostAsync = function()
					env.posts += 1
					if env.posts <= env.failPosts then
						error(env.postError)
					end
				end,
			},
		}, {
			os = {
				clock = function()
					return env.clock
				end,
				date = os.date,
				time = os.time,
			},
			warn = function(...)
				table.insert(env.warns, table.concat({ ... }, " "))
			end,
			print = function(...)
				table.insert(env.prints, table.concat({ ... }, " "))
			end,
			task = {
				spawn = function(fn, ...)
					table.insert(env.spawned, table.pack(fn, ...))
				end,
				wait = function(seconds)
					table.insert(env.waits, seconds)
				end,
			},
		})
		env.CheatLog = loader:require("src/server/CheatLog")
		env.N = loader:require("src/shared/NetworkProtocol").Names
		-- Cette méthode permet d'exécuter l'envoi lancé en i-ème lorsqu'un test vérifie ce qui part au webhook.
		function env.run(i: number)
			local spawned = env.spawned[i]
			spawned[1](table.unpack(spawned, 2, spawned.n))
		end
		return env
	end

	-- Cette méthode permet de créer un faux joueur qui retient son kick lorsqu'un test vérifie la sanction.
	local function fakePlayer(userId: number, name: string)
		local player = { UserId = userId, Name = name, Parent = {}, kickedWith = nil :: string? }
		function player.Kick(self, message)
			self.kickedWith = message
		end
		return player
	end

	-- Cette méthode permet de construire le participant d'un faux joueur lorsqu'on appelle CheatLog.report.
	local function participantOf(player): any
		return { id = player.UserId, name = player.Name, isBot = false, player = player }
	end

	T.describe("CheatLog noms partagés", function()
		T.it("ré-exporte les gravités et catégories de CheatTypes (une seule source, lue par ShotRules)", function()
			local C = setup().CheatLog
			local Types = Loader.new():require("src/server/CheatTypes")
			for name, value in Types.Category do
				T.expectEqual(C.Category[name], value, "catégorie " .. name)
			end
			for name, value in Types.Severity do
				T.expectEqual(C.Severity[name], value, "gravité " .. name)
			end
			local ShotRules = Loader.new():require("src/server/ShotRules")
			T.expectEqual(ShotRules.SEVERITY.shape, Types.Severity.HIGH)
			T.expectEqual(ShotRules.SEVERITY.origin, Types.Severity.MEDIUM)
		end)
	end)

	T.describe("CheatLog.report", function()
		T.it("compte par catégorie et gravité et garde la pire violation", function()
			local env = setup()
			local C = env.CheatLog
			local alice = participantOf(fakePlayer(1, "Alice"))
			C.report(alice, C.Category.REMOTE_RATE, C.Severity.LOW, "flood")
			C.report(alice, C.Category.REMOTE_RATE, C.Severity.LOW, "flood")
			C.report(alice, C.Category.MOVEMENT, C.Severity.MEDIUM, "téléport")
			local summary = C.summary(1)
			T.expectEqual(summary.total, 3)
			T.expectEqual(summary.counts.RemoteRate.low, 2)
			T.expectEqual(summary.counts.Movement.medium, 1)
			T.expectEqual(summary.worst.category, "Movement")
			T.expectEqual(C.summary(2), nil, "pas de bilan sans violation")
		end)

		T.it("fait décroître le score dans le temps (seau qui fuit)", function()
			local env = setup()
			local C = env.CheatLog
			local alice = participantOf(fakePlayer(1, "Alice"))
			C.report(alice, C.Category.MOVEMENT, C.Severity.MEDIUM, "a")
			C.report(alice, C.Category.MOVEMENT, C.Severity.MEDIUM, "b")
			T.expectEqual(C.summary(1).score, 2 * C.SCORE_WEIGHT.medium)
			env.clock = 4
			T.expectNear(C.summary(1).score, 2 * C.SCORE_WEIGHT.medium - 4 * C.SCORE_DECAY)
			env.clock = 1000
			T.expectEqual(C.summary(1).score, 0, "jamais négatif")
			T.expectEqual(C.summary(1).maxScore, 2 * C.SCORE_WEIGHT.medium, "le maximum reste au bilan")
		end)

		T.it("limite les warns par joueur et compte ceux qui sont tus", function()
			local env = setup()
			local C = env.CheatLog
			local alice = participantOf(fakePlayer(1, "Alice"))
			for _ = 1, 10 do
				C.report(alice, C.Category.REMOTE_RATE, C.Severity.LOW, "flood")
			end
			T.expectEqual(#env.warns, 1)
			env.clock = C.WARN_INTERVAL
			C.report(alice, C.Category.REMOTE_RATE, C.Severity.LOW, "flood")
			T.expectEqual(#env.warns, 2)
			T.expect(string.find(env.warns[2], "+9", 1, true) ~= nil, "le warn suivant annonce les 9 tus")
		end)

		T.it("coupe un détail trop long sans casser l'UTF-8", function()
			local env = setup()
			local C = env.CheatLog
			C.report(participantOf(fakePlayer(1, "Alice")), "X", C.Severity.LOW, string.rep("a", 5000))
			T.expect(#C.summary(1).worst.detail <= C.MAX_DETAIL + 3)
			C.report(participantOf(fakePlayer(2, "Bob")), "X", C.Severity.MEDIUM, "a" .. string.rep("é", 200))
			local detail = C.summary(2).worst.detail
			T.expect(utf8.len(detail) ~= nil, "é coupé au milieu")
			T.expect(#detail <= C.MAX_DETAIL + 3)
			C.report(participantOf(fakePlayer(3, "Eve")), "X", C.Severity.LOW, "reçu \255 é")
			T.expectEqual(C.summary(3).worst.detail, "reçu ? é", "seul l'octet invalide est remplacé")
		end)

		T.it("remplace les octets non UTF-8 d'une valeur forgée", function()
			local env = setup()
			local C = env.CheatLog
			C.report(participantOf(fakePlayer(1, "Alice")), "X", C.Severity.LOW, "val \255\254 fin")
			local detail = C.summary(1).worst.detail
			T.expect(utf8.len(detail) ~= nil)
			T.expectEqual(detail, "val ?? fin")
		end)

		T.it("expulse à la 3e violation forte, une seule fois", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			local alice = participantOf(player)
			for _ = 1, 20 do
				C.report(alice, C.Category.REMOTE_RATE, C.Severity.LOW, "flood")
			end
			C.report(alice, C.Category.MOVEMENT, C.Severity.MEDIUM, "téléport")
			T.expectEqual(player.kickedWith, nil, "faibles et moyennes : jamais de kick")
			C.report(alice, C.Category.REMOTE_ARGS, C.Severity.HIGH, "NaN")
			env.clock += C.HIGH_SOURCE_INTERVAL
			C.report(alice, C.Category.REMOTE_ARGS, C.Severity.HIGH, "NaN")
			T.expectEqual(player.kickedWith, nil, "2 fortes")
			env.clock += C.HIGH_SOURCE_INTERVAL
			C.report(alice, C.Category.REMOTE_ARGS, C.Severity.HIGH, "NaN")
			T.expectEqual(player.kickedWith, C.KICK_MESSAGE)
			T.expectEqual(C.summary(1).kicked, true)
			player.kickedWith = nil
			env.clock += C.HIGH_SOURCE_INTERVAL
			C.report(alice, C.Category.REMOTE_ARGS, C.Severity.HIGH, "NaN")
			T.expectEqual(player.kickedWith, nil, "pas de second kick")
		end)

		T.it("ne sanctionne pas dans Studio, mais journalise", function()
			local env = setup(true)
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			for _ = 1, 5 do
				C.report(participantOf(player), C.Category.REMOTE_ARGS, C.Severity.HIGH, "NaN")
				env.clock += C.HIGH_SOURCE_INTERVAL
			end
			T.expectEqual(player.kickedWith, nil)
			T.expectEqual(C.summary(1).highCount, 5)
		end)

		T.it("ne compte qu'une violation forte par source et par intervalle pour le kick", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			-- Bug client : position NaN envoyée à 20 Hz pendant une demi-seconde
			for _ = 1, 10 do
				C.report(participantOf(player), C.Category.REMOTE_ARGS, C.Severity.HIGH, "NaN", "CharacterSync")
				env.clock += 0.05
			end
			T.expectEqual(player.kickedWith, nil, "rafale d'une même source : une seule comptée")
			local summary = C.summary(1)
			T.expectEqual(summary.highCount, 1)
			T.expectEqual(summary.counts.RemoteArgs.high, 10, "toutes au journal")
			-- Sources différentes au même instant : chacune compte
			C.report(participantOf(player), C.Category.REMOTE_ARGS, C.Severity.HIGH, "x", "MeleeDamage")
			C.report(participantOf(player), C.Category.REMOTE_ARGS, C.Severity.HIGH, "x", "HitscanDamage")
			T.expectEqual(player.kickedWith, C.KICK_MESSAGE)
		end)

		T.it("ignore les bots", function()
			local env = setup()
			local C = env.CheatLog
			C.report({ id = -1, name = "Marcel", isBot = true }, C.Category.MELEE, C.Severity.HIGH, "x")
			T.expectEqual(C.summary(-1), nil)
			T.expectEqual(#env.warns, 0)
		end)

		T.it("refuse une gravité inconnue (bug d'appelant)", function()
			local env = setup()
			local ok = pcall(env.CheatLog.report, participantOf(fakePlayer(1, "Alice")), "X", "critique", "x")
			T.expectEqual(ok, false)
		end)
	end)

	T.describe("CheatLog départ et résumé", function()
		T.it("résume un joueur qui part avec des violations, puis l'oublie", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			C.report(participantOf(player), C.Category.REMOTE_ARGS, C.Severity.HIGH, "MeleeDamage : arg 2")
			C.onPlayerRemoving(player :: any)
			T.expectEqual(#env.spawned, 1, "résumé lancé dans son propre fil")
			T.expectEqual(C.summary(1), nil)
			local embed = C.buildEmbed(env.spawned[1][2])
			T.expect(string.find(embed.footer.text, "UserId 1", 1, true) ~= nil, "UserId au résumé")
			T.expect(string.find(embed.description, "MeleeDamage", 1, true) ~= nil, "pire violation au résumé")
			T.expectEqual(embed.fields[1].name, "RemoteArgs")
		end)

		T.it("n'envoie rien pour un joueur sans violation", function()
			local env = setup()
			env.CheatLog.onPlayerRemoving(fakePlayer(2, "Bob") :: any)
			T.expectEqual(#env.spawned, 0)
		end)

		T.it("n'envoie rien pour quelques violations faibles (rafale réseau)", function()
			local env = setup()
			local C = env.CheatLog
			local bob = fakePlayer(2, "Bob")
			for _ = 1, C.SUMMARY_MIN_LOW - 1 do
				C.report(participantOf(bob), C.Category.REMOTE_RATE, C.Severity.LOW, "rafale")
			end
			C.onPlayerRemoving(bob :: any)
			T.expectEqual(#env.spawned, 0)
			T.expectEqual(C.summary(2), nil, "bilan oublié quand même")
		end)

		T.it("envoie un résumé dès une violation moyenne, ou au seuil de violations faibles", function()
			local env = setup()
			local C = env.CheatLog
			local bob, eve = fakePlayer(2, "Bob"), fakePlayer(3, "Eve")
			C.report(participantOf(bob), C.Category.MOVEMENT, C.Severity.MEDIUM, "téléport")
			C.onPlayerRemoving(bob :: any)
			T.expectEqual(#env.spawned, 1, "une moyenne suffit")
			for _ = 1, C.SUMMARY_MIN_LOW do
				C.report(participantOf(eve), C.Category.REMOTE_RATE, C.Severity.LOW, "flood")
			end
			C.onPlayerRemoving(eve :: any)
			T.expectEqual(#env.spawned, 2, "seuil de faibles atteint")
		end)

		T.it("statistiques de visée (#178) : un signalement faible suffit au résumé, jamais de kick", function()
			local env = setup()
			local C = env.CheatLog
			local bob = fakePlayer(2, "Bob")
			for _ = 1, 3 * C.KICK_HIGH_COUNT do
				C.report(participantOf(bob), C.Category.AIM, C.Severity.LOW, "SIGNALÉ tête z+8.0", C.Category.AIM)
			end
			T.expectEqual(bob.kickedWith, nil, "aucune sanction")
			T.expectEqual(C.summary(2).highCount, 0)
			T.expectEqual(C.summary(2).total, 0, "un relevé de visée n'est pas une violation")
			T.expectEqual(C.summary(2).score, 0)
			T.expectEqual(C.summary(2).counts.Aim.low, 3 * C.KICK_HIGH_COUNT)
			-- Une vraie violation juste après reste affichée (le relevé ne prend pas le créneau du warn limité)
			local before = #env.warns
			C.report(participantOf(bob), C.Category.REMOTE_RATE, C.Severity.LOW, "flood")
			T.expectEqual(#env.warns, before + 1)
			C.onPlayerRemoving(bob :: any)
			T.expectEqual(#env.spawned, 1, "résumé envoyé pour revue humaine")
			local embed = C.buildEmbed(env.spawned[1][2])
			T.expect(string.find(embed.description, "Visée", 1, true) ~= nil, "relevé de visée au résumé")
			T.expect(string.find(embed.description, "RemoteRate", 1, true) ~= nil, "pire violation réelle au résumé")
		end)

		T.it("rappel de clôture : son signalement entre au résumé même sans Parent, avant l'oubli", function()
			local env = setup()
			local C = env.CheatLog
			local bob = fakePlayer(2, "Bob")
			local seen = 0
			C.onClosing(function(players)
				for _, player in players do
					seen += 1
					C.report(participantOf(player), C.Category.AIM, C.Severity.LOW, "fin de session")
				end
			end)
			C.onClosing(function()
				error("rappel cassé")
			end)
			-- PlayerRemoving différé : le joueur n'a déjà plus de Parent
			bob.Parent = nil
			C.onPlayerRemoving(bob :: any)
			T.expectEqual(seen, 1)
			T.expectEqual(#env.spawned, 1, "résumé envoyé malgré un rappel en erreur")
			T.expectEqual(C.summary(2), nil, "bilan oublié")
			-- Hors clôture, un joueur parti reste ignoré
			C.report(participantOf(bob), C.Category.AIM, C.Severity.LOW, "tardif")
			T.expectEqual(C.summary(2), nil)
		end)

		T.it("ignore une violation signalée après le départ", function()
			local env = setup()
			local C = env.CheatLog
			local bob = fakePlayer(2, "Bob")
			bob.Parent = nil
			C.report(participantOf(bob), C.Category.MOVEMENT, C.Severity.HIGH, "tardive")
			T.expectEqual(C.summary(2), nil)
		end)
	end)

	T.describe("CheatLog mesure (#297)", function()
		T.it("compte chaque contrôle à part, sous Catégorie:contrôle", function()
			local env = setup()
			local C = env.CheatLog
			local alice = participantOf(fakePlayer(1, "Alice"))
			C.report(alice, C.Category.HITSCAN, C.Severity.MEDIUM, "direction : a", "direction")
			C.report(alice, C.Category.HITSCAN, C.Severity.MEDIUM, "direction : b", "direction")
			C.report(alice, C.Category.HITSCAN, C.Severity.MEDIUM, "origin : c", "origin")
			C.report(alice, C.Category.SPAWN, C.Severity.LOW, "alive")
			C.report(alice, C.Category.AIM, C.Severity.LOW, "relevé", C.Category.AIM)
			local summary = C.summary(1)
			T.expectEqual(summary.checks["Hitscan:direction"].medium, 2)
			T.expectEqual(summary.checks["Hitscan:origin"].medium, 1)
			T.expectEqual(summary.counts.Hitscan.medium, 3, "la catégorie compte toujours le total")
			T.expectEqual(summary.checks.Spawn.low, 1, "sans contrôle nommé : la catégorie seule")
			T.expectEqual(summary.checks.Aim.low, 1, "contrôle nommé comme sa catégorie : pas de doublon")
			T.expectEqual(summary.checks["Aim:Aim"], nil)
		end)

		T.it("garde des remotes : le remote est le contrôle, débit compris", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			for _ = 1, 50 do
				C.admit(player :: any, env.N.REQUEST_SPAWN)
			end
			C.admit(player :: any, env.N.MELEE_DAMAGE, Instance.new("Model"), "kill", 0)
			local summary = C.summary(1)
			T.expect(summary.checks["RemoteRate:" .. env.N.REQUEST_SPAWN].low > 0)
			T.expectEqual(summary.checks["RemoteArgs:" .. env.N.MELEE_DAMAGE].high, 1)
		end)

		T.it("dénominateurs par joueur, avec ou sans violation ; bots et joueurs partis ignorés", function()
			local env = setup()
			local C = env.CheatLog
			local alice, bob = participantOf(fakePlayer(1, "Alice")), participantOf(fakePlayer(2, "Bob"))
			for _ = 1, 3 do
				C.judged(alice, C.Judged.SHOT)
			end
			C.judged(alice, C.Judged.MELEE)
			for _ = 1, 5 do
				C.judged(bob, C.Judged.POSITION)
			end
			C.judged({ id = -1, name = "Marcel", isBot = true }, C.Judged.SHOT)
			local gone = fakePlayer(3, "Eve")
			gone.Parent = nil
			C.judged(participantOf(gone), C.Judged.SHOT)
			T.expectEqual(C.session(1).judged.shot, 3)
			T.expectEqual(C.session(1).judged.melee, 1)
			T.expectEqual(C.session(2).judged.position, 5)
			T.expectEqual(C.summary(2), nil, "pas de bilan sans violation, mais une session")
			T.expectEqual(C.session(-1), nil, "bot ignoré")
			T.expectEqual(C.session(3), nil, "joueur parti ignoré")
			-- PlayerRemoving arrive avant que Parent passe à nil : un paquet traité juste après ne recrée rien
			local leaving = fakePlayer(4, "Zoé")
			C.judged(participantOf(leaving), C.Judged.POSITION)
			C.onPlayerRemoving(leaving :: any)
			T.expect(leaving.Parent ~= nil)
			C.judged(participantOf(leaving), C.Judged.POSITION)
			C.report(participantOf(leaving), C.Category.MOVEMENT, C.Severity.MEDIUM, "tardif", "speed")
			T.expectEqual(C.session(4), nil, "session non recréée après le départ")
			T.expectEqual(C.summary(4), nil, "bilan non recréé après le départ")
			C.report(alice, C.Category.HITSCAN, C.Severity.MEDIUM, "x", "direction")
			T.expectEqual(C.summary(1).judged.shot, 3, "jugés joints au bilan")
		end)

		T.it("ping de la session : médiane à la classe près et maximum, valeurs absurdes ignorées", function()
			local env = setup()
			local C = env.CheatLog
			local alice = participantOf(fakePlayer(1, "Alice"))
			for _, seconds in { 0.05, 0.08, 0.2, 0 / 0, -1, math.huge } do
				C.notePing(alice, seconds)
			end
			local ping = C.session(1).ping
			T.expectEqual(ping.samples, 3)
			T.expectEqual(ping.medianMs, 85, "classe 80-90 ms")
			T.expectNear(ping.maxMs, 200)
			-- Ping nul (Studio) : la médiane ne dépasse pas le maximum
			local bob = participantOf(fakePlayer(2, "Bob"))
			C.notePing(bob, 0)
			T.expectEqual(C.session(2).ping.medianMs, 0)
		end)

		T.it("pire violation : la plus grave, puis celle du contrôle le plus répété", function()
			local env = setup()
			local C = env.CheatLog
			local alice = participantOf(fakePlayer(1, "Alice"))
			C.report(alice, C.Category.HITSCAN, C.Severity.MEDIUM, "origin : isolée", "origin")
			T.expectEqual(C.summary(1).worst.check, "Hitscan:origin")
			C.report(alice, C.Category.HITSCAN, C.Severity.MEDIUM, "direction : 1", "direction")
			T.expectEqual(C.summary(1).worst.check, "Hitscan:direction", "égalité : la plus récente")
			C.report(alice, C.Category.HITSCAN, C.Severity.MEDIUM, "direction : 2", "direction")
			C.report(alice, C.Category.HITSCAN, C.Severity.MEDIUM, "direction : 3", "direction")
			C.report(alice, C.Category.HITSCAN, C.Severity.MEDIUM, "origin : 2, moins répétée", "origin")
			T.expectEqual(C.summary(1).worst.detail, "direction : 3", "contrôle le plus répété, dernier détail")
			C.report(alice, C.Category.REMOTE_RATE, C.Severity.LOW, "flood", "X")
			T.expectEqual(C.summary(1).worst.check, "Hitscan:direction", "une faible ne remplace pas une moyenne")
			C.report(alice, C.Category.REMOTE_ARGS, C.Severity.HIGH, "NaN", "CharacterSync")
			T.expectEqual(C.summary(1).worst.check, "RemoteArgs:CharacterSync", "une forte l'emporte")
		end)

		T.it("résumé : contrôles avec leur taux, jugés et ping du joueur", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			local alice = participantOf(player)
			for _ = 1, 4 do
				C.judged(alice, C.Judged.SHOT)
			end
			C.notePing(alice, 0.08)
			C.report(alice, C.Category.HITSCAN, C.Severity.MEDIUM, "direction : a", "direction")
			C.report(alice, C.Category.MOVEMENT, C.Severity.LOW, "vide", "void")
			C.onPlayerRemoving(player :: any)
			T.expectEqual(C.session(1), nil, "session oubliée au départ")
			local embed = C.buildEmbed(env.spawned[1][2])
			T.expect(string.find(embed.description, "Jugés : 4 touches · 0 coups · 0 positions", 1, true) ~= nil)
			T.expect(string.find(embed.description, "Ping : médiane 80 ms, max 80 ms (1 mesures)", 1, true) ~= nil)
			T.expect(string.find(embed.description, "Pire : Hitscan:direction moyenne", 1, true) ~= nil)
			local byName = {}
			for _, field in embed.fields do
				byName[field.name] = field.value
			end
			T.expect(string.find(byName.Hitscan, "direction 1 / 4 touches (25.00 %)", 1, true) ~= nil, byName.Hitscan)
			T.expect(string.find(byName.Movement, "void 1", 1, true) ~= nil, "vide : sans dénominateur")
			T.expect(string.find(byName.Movement, "positions", 1, true) == nil, byName.Movement)
			T.expectEqual(C.denominatorOf("Hitscan:orphanRate"), nil, "signalé par palier, pas par touche")
			T.expectEqual(C.denominatorOf("Hitscan:shotLink"), "shot")
			T.expectEqual(C.denominatorOf("RemoteRate:ShotFired"), nil)
		end)

		T.it("embed borné aux limites de Discord : lignes en trop résumées", function()
			local env = setup()
			local C = env.CheatLog
			local alice = participantOf(fakePlayer(1, "Alice"))
			for i = 1, 200 do
				C.report(alice, C.Category.REMOTE_RATE, C.Severity.LOW, "flood", string.format("RemoteNumero%03d", i))
			end
			local embed = C.buildEmbed(C.summary(1))
			local value = embed.fields[1].value
			T.expect(utf8.len(value) <= C.MAX_FIELD_VALUE, "champ sous la limite : " .. utf8.len(value))
			T.expect(string.find(value, "… (+", 1, true) ~= nil, "lignes coupées annoncées")
			T.expectEqual(C.joinCapped({ "a", "b" }, 100), "a\nb", "rien coupé sous la limite")
			-- Dernière ligne trop longue : coupée elle aussi
			local capped = C.joinCapped({ "a", string.rep("x", 200) }, 50)
			T.expect(utf8.len(capped) <= 50, capped)
			T.expectEqual(capped, "a\n… (+1)")
		end)

		T.it("embed entier sous la limite totale, même avec beaucoup de catégories pleines", function()
			local env = setup()
			local C = env.CheatLog
			local alice = participantOf(fakePlayer(1, "Alice"))
			for c = 1, 10 do
				for i = 1, 80 do
					C.report(alice, "Categorie" .. c, C.Severity.LOW, "x", string.format("ControleAuNomLong%03d", i))
				end
			end
			local embed = C.buildEmbed(C.summary(1))
			local total = utf8.len(embed.title) + utf8.len(embed.description) + utf8.len(embed.footer.text)
			for _, field in embed.fields do
				total += utf8.len(field.name) + utf8.len(field.value)
			end
			T.expect(total <= 6000, "embed de " .. total .. " caractères")
		end)

		T.it("relevé agrégé : taux par contrôle sur les jugés de tous, joueurs sans violation compris", function()
			local env = setup()
			local C = env.CheatLog
			local alice, bob = fakePlayer(1, "Alice"), fakePlayer(2, "Bob")
			for _ = 1, 3 do
				C.judged(participantOf(alice), C.Judged.SHOT)
			end
			for _ = 1, 7 do
				C.judged(participantOf(bob), C.Judged.SHOT)
				C.judged(participantOf(bob), C.Judged.POSITION)
			end
			C.notePing(participantOf(bob), 0.1)
			C.report(participantOf(alice), C.Category.HITSCAN, C.Severity.MEDIUM, "a", "direction")
			C.report(participantOf(alice), C.Category.HITSCAN, C.Severity.MEDIUM, "b", "direction")
			C.report(participantOf(alice), C.Category.REMOTE_RATE, C.Severity.LOW, "flood", "ShotFired")
			-- Alice part avant le relevé : ce qu'elle a fait y reste
			C.onPlayerRemoving(alice :: any)
			env.clock = 120
			local embed = C.flushReport("périodique")
			T.expect(embed ~= nil)
			local text = embed.description
			T.expect(string.find(text, "Période de 2.0 min (périodique)", 1, true) ~= nil, text)
			T.expect(string.find(text, "Joueurs : 2, dont 1 avec violation", 1, true) ~= nil, text)
			T.expect(string.find(text, "Jugés : 10 touches · 0 coups · 7 positions", 1, true) ~= nil, text)
			T.expect(string.find(text, "Hitscan:direction : 2 / 10 touches (20.00 %)", 1, true) ~= nil, text)
			T.expect(string.find(text, "RemoteRate:ShotFired : 1", 1, true) ~= nil, "sans dénominateur : nombre brut")
			T.expect(string.find(text, "Ping : médiane 100 ms, max 100 ms", 1, true) ~= nil, text)
			-- Envoi lancé dans son propre fil ; la période suivante repart de zéro
			T.expectEqual(env.spawned[#env.spawned][2], embed)
			T.expectEqual(C.flushReport("périodique"), nil, "période vide : rien d'émis")
			C.judged(participantOf(bob), C.Judged.POSITION)
			local last = C.flushReport("arrêt du serveur")
			T.expect(string.find(last.description, "Jugés : 0 touches · 0 coups · 1 positions", 1, true) ~= nil)
			T.expect(string.find(last.description, "Aucune violation.", 1, true) ~= nil)
		end)

		T.it("relevé : les relevés de visée sont à part, pas des contrôles en violation", function()
			local env = setup()
			local C = env.CheatLog
			C.report(participantOf(fakePlayer(1, "Alice")), C.Category.AIM, C.Severity.LOW, "SIGNALÉ", C.Category.AIM)
			local text = C.flushReport("périodique").description
			T.expect(string.find(text, "Relevés de visée signalés : 1", 1, true) ~= nil, text)
			T.expect(string.find(text, "Aucune violation.", 1, true) ~= nil, text)
			T.expect(string.find(text, "dont 0 avec violation", 1, true) ~= nil, text)
		end)

		T.it("relevé : webhook dédié seulement, sinon console (jamais le salon du feedback)", function()
			local env = setup()
			local C = env.CheatLog
			env.webhooks.FeedbackWebhookUrl = "https://exemple.invalid/feedback"
			C.judged(participantOf(fakePlayer(1, "Alice")), C.Judged.SHOT)
			C.flushReport("périodique")
			env.run(#env.spawned)
			T.expectEqual(env.posts, 0, "pas au webhook du feedback")
			T.expect(string.find(table.concat(env.prints, "\n"), "relevé du serveur :", 1, true) ~= nil)
			T.expectEqual(#env.warns, 0, "réglage prévu : console sans avertissement")
			env.webhooks.CheatLogWebhookUrl = "https://exemple.invalid/anticheat"
			C.judged(participantOf(fakePlayer(1, "Alice")), C.Judged.SHOT)
			C.flushReport("périodique")
			env.run(#env.spawned)
			T.expectEqual(env.posts, 1, "posté au webhook dédié")
		end)

		T.it("arrêt du serveur : dernier relevé émis, puis plus rien compté (pas de second résumé)", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			env.players = { player }
			C.judged(participantOf(player), C.Judged.SHOT)
			C.report(participantOf(player), C.Category.MOVEMENT, C.Severity.MEDIUM, "téléport", "speed")
			C.close()
			T.expectEqual(#env.spawned, 2, "résumé et relevé lancés")
			-- PlayerRemoving traité après BindToClose : rien de recréé
			C.report(participantOf(player), C.Category.MOVEMENT, C.Severity.MEDIUM, "tardive", "speed")
			C.judged(participantOf(player), C.Judged.SHOT)
			C.onPlayerRemoving(player :: any)
			T.expectEqual(#env.spawned, 2, "pas de second résumé")
			T.expectEqual(C.summary(1), nil)
			T.expectEqual(C.session(1), nil)
		end)

		T.it("webhook : nouvel essai après un échec, sans repli console", function()
			local env = setup()
			local C = env.CheatLog
			env.webhooks.CheatLogWebhookUrl = "https://exemple.invalid/hook"
			env.failPosts = C.WEBHOOK_ATTEMPTS - 1
			local player = fakePlayer(1, "Alice")
			C.report(participantOf(player), C.Category.MOVEMENT, C.Severity.MEDIUM, "téléport", "speed")
			C.onPlayerRemoving(player :: any)
			local before = #env.warns
			env.run(1)
			T.expectEqual(env.posts, C.WEBHOOK_ATTEMPTS, "posté au dernier essai")
			T.expectEqual(#env.waits, C.WEBHOOK_ATTEMPTS - 1)
			T.expectEqual(env.waits[1], C.WEBHOOK_RETRY_DELAY)
			T.expectEqual(env.waits[2], 2 * C.WEBHOOK_RETRY_DELAY, "attente croissante")
			T.expectEqual(#env.warns, before, "rien en console : le résumé est parti")
		end)

		T.it("webhook : après le dernier essai, le résumé entier part en console", function()
			local env = setup()
			local C = env.CheatLog
			env.webhooks.FeedbackWebhookUrl = "https://exemple.invalid/hook"
			env.failPosts = math.huge
			local player = fakePlayer(1, "Alice")
			C.report(participantOf(player), C.Category.MOVEMENT, C.Severity.MEDIUM, "téléport refusé", "speed")
			C.onPlayerRemoving(player :: any)
			env.run(1)
			T.expectEqual(env.posts, C.WEBHOOK_ATTEMPTS)
			local console = table.concat(env.warns, "\n")
			T.expect(string.find(console, "après " .. C.WEBHOOK_ATTEMPTS .. " essai(s)", 1, true) ~= nil, console)
			T.expect(string.find(console, "repli console", 1, true) ~= nil, console)
			T.expect(string.find(console, "téléport refusé", 1, true) ~= nil, "détail du résumé gardé")
			T.expect(string.find(console, "UserId 1", 1, true) ~= nil, "UserId gardé")
		end)

		T.it("webhook : pas de nouvel essai sur un refus définitif (HTTP 4xx autre que 429)", function()
			local env = setup()
			local C = env.CheatLog
			env.webhooks.CheatLogWebhookUrl = "https://exemple.invalid/hook"
			env.failPosts = math.huge
			env.postError = "HTTP 400 (Bad Request)"
			local player = fakePlayer(1, "Alice")
			C.report(participantOf(player), C.Category.MOVEMENT, C.Severity.MEDIUM, "téléport", "speed")
			C.onPlayerRemoving(player :: any)
			env.run(1)
			T.expectEqual(env.posts, 1, "un seul essai")
			T.expectEqual(#env.waits, 0)
			T.expect(string.find(table.concat(env.warns, "\n"), "repli console", 1, true) ~= nil)
		end)

		T.it("webhook : erreurs définitives et passagères reconnues", function()
			local Webhook = Loader.new({ HttpService = {} }):require("src/server/Webhook")
			T.expectEqual(Webhook.isRetryable("HTTP 429 (Too Many Requests)"), true)
			T.expectEqual(Webhook.isRetryable("HTTP 502 (Bad Gateway)"), true)
			T.expectEqual(Webhook.isRetryable("HttpError: Timedout"), true)
			T.expectEqual(Webhook.isRetryable("HTTP 400 (Bad Request)"), false)
			T.expectEqual(Webhook.isRetryable("HTTP 404 (Not Found)"), false)
			T.expectEqual(Webhook.isRetryable("Http requests are not enabled. Enable via game settings"), false)
		end)

		T.it("webhook absent : repli console, rien posté ; Studio : résumé complet affiché", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			C.report(participantOf(player), C.Category.MOVEMENT, C.Severity.MEDIUM, "téléport", "speed")
			C.onPlayerRemoving(player :: any)
			env.run(1)
			T.expectEqual(env.posts, 0)
			local console = table.concat(env.warns, "\n")
			T.expect(string.find(console, "aucun webhook configuré", 1, true) ~= nil, console)
			T.expect(string.find(console, "Movement : ", 1, true) ~= nil, "champs du résumé en console")

			local studio = setup(true)
			local S = studio.CheatLog
			studio.webhooks.CheatLogWebhookUrl = "https://exemple.invalid/hook"
			local bob = fakePlayer(2, "Bob")
			S.report(participantOf(bob), S.Category.MOVEMENT, S.Severity.MEDIUM, "téléport", "speed")
			S.onPlayerRemoving(bob :: any)
			studio.run(1)
			T.expectEqual(studio.posts, 0, "jamais de webhook depuis Studio")
			local printed = table.concat(studio.prints, "\n")
			T.expect(string.find(printed, "résumé de Bob", 1, true) ~= nil, printed)
			T.expect(string.find(printed, "Jugés :", 1, true) ~= nil, printed)
		end)
	end)

	T.describe("CheatLog.admit", function()
		T.it("laisse passer un appel honnête sans rien journaliser", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			T.expectEqual(C.admit(player :: any, env.N.WEAPON_ACTION, "Shoot"), true)
			T.expectEqual(C.summary(1), nil)
		end)

		T.it("débit dépassé : appel ignoré, violation faible", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			local accepted = 0
			for _ = 1, 50 do
				if C.admit(player :: any, env.N.REQUEST_SPAWN) then
					accepted += 1
				end
			end
			T.expect(accepted < 50, "flood coupé")
			local summary = C.summary(1)
			T.expectEqual(summary.counts.RemoteRate.low, 50 - accepted)
			T.expectEqual(summary.highCount, 0)
			T.expectEqual(player.kickedWith, nil)
		end)

		T.it("type impossible : appel ignoré, violation forte, kick à la 3e", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			T.expectEqual(C.admit(player :: any, env.N.MELEE_DAMAGE, Instance.new("Model"), "kill", 0), false)
			T.expectEqual(C.summary(1).counts.RemoteArgs.high, 1)
			C.admit(player :: any, env.N.CHARACTER_SYNC, Vector3.new(0 / 0, 0, 0), 0, 0, false)
			C.admit(player :: any, env.N.SAVE_SETTINGS, "x")
			T.expectEqual(player.kickedWith, C.KICK_MESSAGE)
		end)

		T.it("remote sans règle : refusé sans violation (bug du serveur)", function()
			local env = setup()
			local C = env.CheatLog
			T.expectEqual(C.admit(fakePlayer(1, "Alice") :: any, "RemoteOublie"), false)
			T.expectEqual(C.summary(1), nil)
			T.expectEqual(#env.warns, 1)
			C.admit(fakePlayer(1, "Alice") :: any, "RemoteOublie")
			T.expectEqual(#env.warns, 1, "signalé une seule fois")
		end)

		T.it("joueur déjà parti : appel ignoré, rien de recréé", function()
			local env = setup()
			local C = env.CheatLog
			local player = fakePlayer(1, "Alice")
			player.Parent = nil
			T.expectEqual(C.admit(player :: any, env.N.MELEE_DAMAGE, Instance.new("Model"), "kill", 0), false)
			T.expectEqual(C.summary(1), nil)
		end)

		T.it("Instance absente : appel ignoré sans violation", function()
			local env = setup()
			local C = env.CheatLog
			T.expectEqual(C.admit(fakePlayer(1, "Alice") :: any, env.N.HITSCAN_DAMAGE, nil, nil), false)
			T.expectEqual(C.summary(1), nil)
		end)
	end)
end
