-- Journal des violations (#170) : compteurs, score décroissant, warn limité, kick à 3 violations fortes, bots et
-- Studio sans sanction, résumé au départ, garde des remotes branchée sur le journal.
return function(T, Loader)
	-- Cette méthode permet de monter un CheatLog neuf avec horloge, console, Studio et `task` simulés lorsqu'un test
	-- démarre ; spawned garde les résumés lancés au départ d'un joueur (sans les exécuter).
	local function setup(isStudio: boolean?)
		local env = { clock = 0, warns = {}, prints = {}, spawned = {} }
		local loader = Loader.new({
			Players = {
				PlayerRemoving = {
					Connect = function() end,
				},
			},
			RunService = {
				IsStudio = function()
					return isStudio == true
				end,
			},
			HttpService = {},
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
			},
		})
		env.CheatLog = loader:require("src/server/CheatLog")
		env.N = loader:require("src/shared/NetworkProtocol").Names
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
			T.expectEqual(C.admit(player :: any, env.N.MELEE_DAMAGE, Instance.new("Model"), "kill"), false)
			T.expectEqual(C.summary(1).counts.RemoteArgs.high, 1)
			C.admit(player :: any, env.N.CHARACTER_SYNC, Vector3.new(0 / 0, 0, 0), 0)
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
			T.expectEqual(C.admit(player :: any, env.N.MELEE_DAMAGE, Instance.new("Model"), "kill"), false)
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
