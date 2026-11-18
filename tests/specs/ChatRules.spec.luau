-- Chat (#541) : nettoyage, longueur, débit, fondu du fil, commandes admin, joueur visé et droits.
return function(T, Loader)
	local ChatRules = Loader.new():require("src/shared/ChatRules")

	T.describe("ChatRules.clean / clip", function()
		T.it("retire les espaces autour et aplatit les retours à la ligne", function()
			T.expectEqual(ChatRules.clean("  salut\ntoi\t "), "salut toi")
			T.expectEqual(ChatRules.clean("   "), "")
		end)

		T.it("coupe à MAX_LENGTH caractères sans casser un caractère accentué", function()
			local long = string.rep("é", ChatRules.MAX_LENGTH + 10)
			local clipped = ChatRules.clip(long)
			T.expectEqual(utf8.len(clipped), ChatRules.MAX_LENGTH)
			T.expectEqual(ChatRules.clip("court"), "court")
		end)
	end)

	T.describe("ChatRules.admit", function()
		T.it("accepte BURST messages d'affilée puis refuse pour débit", function()
			local bucket = ChatRules.newBucket(0)
			for i = 1, ChatRules.BURST do
				T.expectEqual(ChatRules.admit(bucket, "gg", 0, false), "ok", "message " .. i)
			end
			T.expectEqual(ChatRules.admit(bucket, "gg", 0, false), "rate")
		end)

		T.it("regagne un message par 1 / RATE seconde", function()
			local bucket = ChatRules.newBucket(0)
			for _ = 1, ChatRules.BURST do
				ChatRules.admit(bucket, "gg", 0, false)
			end
			T.expectEqual(ChatRules.admit(bucket, "gg", 0.5 / ChatRules.RATE, false), "rate", "demi-jeton")
			T.expectEqual(ChatRules.admit(bucket, "gg", 1 / ChatRules.RATE, false), "ok", "un jeton")
		end)

		T.it("le serveur tolère un message de plus que le client", function()
			local bucket = ChatRules.newBucket(0, ChatRules.SERVER_BURST)
			for i = 1, ChatRules.BURST + 1 do
				T.expectEqual(ChatRules.admit(bucket, "gg", 0, false, ChatRules.SERVER_BURST), "ok", "message " .. i)
			end
			T.expectEqual(ChatRules.admit(bucket, "gg", 0, false, ChatRules.SERVER_BURST), "rate")
		end)

		T.it("refuse sourdine, vide et trop long sans consommer de jeton", function()
			local bucket = ChatRules.newBucket(0)
			T.expectEqual(ChatRules.admit(bucket, "gg", 0, true), "muted")
			T.expectEqual(ChatRules.admit(bucket, "  \n ", 0, false), "empty")
			T.expectEqual(ChatRules.admit(bucket, string.rep("a", ChatRules.MAX_LENGTH + 1), 0, false), "long")
			T.expectEqual(bucket.tokens, ChatRules.BURST, "seau intact")
			T.expectEqual(
				ChatRules.admit(bucket, string.rep("é", ChatRules.MAX_LENGTH), 0, false),
				"ok",
				"limite en caractères"
			)
		end)
	end)

	T.describe("ChatRules.unescape", function()
		T.it("rend les entités du texte riche échappé", function()
			T.expectEqual(
				ChatRules.unescape("a &lt;b&gt; &amp;lt; &quot;c&quot; &apos;d&apos;"),
				"a <b> &lt; \"c\" 'd'"
			)
		end)
	end)

	T.describe("ChatRules.lineTransparency / clampScroll", function()
		T.it("opaque puis effacée en FADE_TIME après FADE_DELAY", function()
			T.expectEqual(ChatRules.lineTransparency(0, false), 0)
			T.expectEqual(ChatRules.lineTransparency(ChatRules.FADE_DELAY, false), 0)
			T.expectNear(ChatRules.lineTransparency(ChatRules.FADE_DELAY + ChatRules.FADE_TIME / 2, false), 0.5)
			T.expectEqual(ChatRules.lineTransparency(ChatRules.FADE_DELAY + ChatRules.FADE_TIME + 1, false), 1)
		end)

		T.it("toutes les lignes réapparaissent saisie ouverte", function()
			T.expectEqual(ChatRules.lineTransparency(1000, true), 0)
		end)

		T.it("borne le défilement entre le bas et la plus ancienne ligne", function()
			T.expectEqual(ChatRules.clampScroll(-3, 20), 0)
			T.expectEqual(ChatRules.clampScroll(100, 20), 20 - ChatRules.FEED_VISIBLE)
			T.expectEqual(ChatRules.clampScroll(2, ChatRules.FEED_VISIBLE - 1), 0, "moins de lignes que la hauteur")
		end)
	end)

	T.describe("ChatRules.parseCommand", function()
		T.it("lit /mute et /unmute avec le joueur visé", function()
			local command, target, reason = ChatRules.parseCommand("/mute Bob")
			T.expectEqual(command, "mute")
			T.expectEqual(target, "Bob")
			T.expectEqual(reason, nil)
			T.expectEqual((ChatRules.parseCommand("/UNMUTE bob")), "unmute", "casse ignorée")
		end)

		T.it("lit /kick avec un motif de plusieurs mots", function()
			local command, target, reason = ChatRules.parseCommand("  /kick Bob insultes répétées ")
			T.expectEqual(command, "kick")
			T.expectEqual(target, "Bob")
			T.expectEqual(reason, "insultes répétées")
		end)

		T.it("une commande sans joueur renvoie la commande seule", function()
			local command, target = ChatRules.parseCommand("/kick")
			T.expectEqual(command, "kick")
			T.expectEqual(target, nil)
			T.expectEqual(ChatRules.usage("kick"), "/kick <joueur> [motif]")
		end)

		T.it("ignore un texte ordinaire ou une commande inconnue", function()
			T.expectEqual((ChatRules.parseCommand("salut /mute")), nil)
			T.expectEqual((ChatRules.parseCommand("/ban Bob")), nil)
			T.expectEqual((ChatRules.parseCommand("/muter Bob")), nil)
		end)
	end)

	T.describe("ChatRules.findTarget", function()
		local players = {
			{ userId = 1, name = "Bobby", displayName = "Bob" },
			{ userId = 2, name = "Bobette", displayName = "Zed" },
			{ userId = 3, name = "Alice", displayName = "Alice" },
		}

		T.it("préfère l'égalité exacte (nom affiché ou d'utilisateur, casse ignorée)", function()
			T.expectEqual((ChatRules.findTarget("bob", players)), 1)
			T.expectEqual((ChatRules.findTarget("BOBETTE", players)), 2)
			T.expectEqual((ChatRules.findTarget("@alice", players)), 3, "@ retiré")
		end)

		T.it("accepte un début de nom unique", function()
			T.expectEqual((ChatRules.findTarget("ali", players)), 3)
			T.expectEqual((ChatRules.findTarget("z", players)), 2)
		end)

		T.it("signale un début ambigu, une absence et une requête vide", function()
			local id, problem = ChatRules.findTarget("bo", players)
			T.expectEqual(id, nil)
			T.expectEqual(problem, "ambiguous")
			T.expectEqual(select(2, ChatRules.findTarget("carl", players)), "none")
			T.expectEqual(select(2, ChatRules.findTarget(nil, players)), "empty")
			T.expectEqual(select(2, ChatRules.findTarget("@", players)), "empty")
		end)
	end)

	T.describe("ChatRules.canModerate", function()
		T.it("Admin seulement, ou attribut de debug dans Studio", function()
			T.expectEqual(ChatRules.canModerate(true, false, false), true)
			T.expectEqual(ChatRules.canModerate(false, false, false), false)
			T.expectEqual(ChatRules.canModerate(false, false, true), false, "debug ignoré hors Studio")
			T.expectEqual(ChatRules.canModerate(false, true, true), true)
			T.expectEqual(ChatRules.canModerate(false, true, false), false)
		end)
	end)
end
