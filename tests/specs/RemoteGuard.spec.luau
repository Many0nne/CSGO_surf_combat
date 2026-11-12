-- Garde commune des remotes (#170) : seau à jetons, contrôles de type, règles de chaque remote.
return function(T, Loader)
	local RemoteGuard = Loader.new():require("src/server/RemoteGuard")
	local NetworkProtocol = Loader.new():require("src/shared/NetworkProtocol")
	local N = NetworkProtocol.Names

	T.describe("RemoteGuard.take (seau à jetons)", function()
		T.it("accepte une rafale de burst appels, puis refuse", function()
			local bucket = RemoteGuard.newBucket(3, 0)
			for i = 1, 3 do
				T.expectEqual(RemoteGuard.take(bucket, 1, 3, 0), true, "appel " .. i)
			end
			T.expectEqual(RemoteGuard.take(bucket, 1, 3, 0), false, "4e appel au même instant")
		end)

		T.it("se remplit au débit et reste plafonné à burst", function()
			local bucket = RemoteGuard.newBucket(2, 0)
			RemoteGuard.take(bucket, 2, 2, 0)
			RemoteGuard.take(bucket, 2, 2, 0)
			T.expectEqual(RemoteGuard.take(bucket, 2, 2, 0.25), false, "un demi-jeton seulement")
			T.expectEqual(RemoteGuard.take(bucket, 2, 2, 0.5), true, "un jeton après 0,5 s à 2/s")
			RemoteGuard.take(bucket, 2, 2, 100)
			T.expectEqual(RemoteGuard.take(bucket, 2, 2, 100), true, "plafond burst = 2")
			T.expectEqual(RemoteGuard.take(bucket, 2, 2, 100), false, "pas plus que burst après un long silence")
		end)

		T.it("ne rend pas de jeton si l'horloge recule", function()
			local bucket = RemoteGuard.newBucket(1, 10)
			RemoteGuard.take(bucket, 1, 1, 10)
			T.expectEqual(RemoteGuard.take(bucket, 1, 1, 5), false)
		end)

		T.it("tient un débit soutenu égal au taux", function()
			local bucket = RemoteGuard.newBucket(2, 0)
			local accepted = 0
			for i = 0, 199 do
				if RemoteGuard.take(bucket, 20, 2, i / 20) then
					accepted += 1
				end
			end
			T.expectEqual(accepted, 200, "20 appels/s à 20 jetons/s : tous acceptés")
		end)
	end)

	T.describe("RemoteGuard contrôles de type", function()
		T.it("instance : Instance acceptée, nil absente, autre type impossible", function()
			local check = RemoteGuard.instance()
			T.expectEqual(check(Instance.new("Model")), "ok")
			T.expectEqual(check(nil), "missing")
			T.expectEqual(check("Model"), "malformed")
			T.expectEqual(check({ Name = "faux" }), "malformed")
			T.expectEqual(check(42), "malformed")
		end)

		T.it("vector3 : fini seulement", function()
			local check = RemoteGuard.vector3()
			T.expectEqual(check(Vector3.new(1, 2, 3)), "ok")
			T.expectEqual(check(Vector3.new(0 / 0, 0, 0)), "malformed", "NaN")
			T.expectEqual(check(Vector3.new(0, math.huge, 0)), "malformed", "+inf")
			T.expectEqual(check(Vector3.new(0, 0, -math.huge)), "malformed", "-inf")
			T.expectEqual(check({ X = 1, Y = 2, Z = 3 }), "malformed", "table imitant un Vector3")
			T.expectEqual(check(nil), "malformed")
		end)

		T.it("number : fini seulement", function()
			local check = RemoteGuard.number()
			T.expectEqual(check(0.5), "ok")
			T.expectEqual(check(-3), "ok")
			T.expectEqual(check(0 / 0), "malformed")
			T.expectEqual(check(math.huge), "malformed")
			T.expectEqual(check("1"), "malformed")
		end)

		T.it("string : bornée en octets", function()
			local check = RemoteGuard.string(5)
			T.expectEqual(check("abcde"), "ok")
			T.expectEqual(check(""), "ok")
			T.expectEqual(check("abcdef"), "malformed")
			T.expectEqual(check(12), "malformed")
		end)

		T.it("enum : valeurs listées seulement", function()
			local check = RemoteGuard.enum({ "Shoot", "Reload" })
			T.expectEqual(check("Shoot"), "ok")
			T.expectEqual(check("Reload"), "ok")
			T.expectEqual(check("shoot"), "malformed", "casse")
			T.expectEqual(check(nil), "malformed")
			T.expectEqual(check(1), "malformed")
			local _, reason = check(string.rep("x", 10000))
			T.expect(#(reason :: string) < 100, "une valeur forgée géante est coupée dans la raison")
		end)

		T.it("table", function()
			local check = RemoteGuard.table()
			T.expectEqual(check({}), "ok")
			T.expectEqual(check("{}"), "malformed")
		end)

		T.it("checkArgs : premier échec, arguments en trop ignorés", function()
			local checks = { RemoteGuard.instance(), RemoteGuard.enum({ "primary" }) }
			T.expectEqual(RemoteGuard.checkArgs(checks, { Instance.new("Model"), "primary", "en trop" }), "ok")
			T.expectEqual(RemoteGuard.checkArgs(checks, { nil, "inconnu" }), "missing", "l'Instance absente d'abord")
			local verdict, reason = RemoteGuard.checkArgs(checks, { Instance.new("Model"), "inconnu" })
			T.expectEqual(verdict, "malformed")
			T.expect(string.find(reason :: string, "arg 2", 1, true) ~= nil, "raison : numéro de l'argument")
		end)
	end)

	T.describe("RemoteGuard.RULES (arguments de notre client)", function()
		-- Cette méthode permet de rejouer un appel tel que notre client l'envoie lorsqu'on vérifie qu'il passe la garde.
		local function honest(remoteName: string, ...: any): string
			local guard = RemoteGuard.new()
			return (guard:check("joueur", remoteName, 0, ...))
		end

		T.it("couvre tous les remotes client → serveur", function()
			for _, name in
				{
					N.MELEE_DAMAGE,
					N.HITSCAN_DAMAGE,
					N.CHARACTER_SYNC,
					N.WEAPON_ACTION,
					N.REQUEST_SPAWN,
					N.LEAVE_ROUND,
					N.SEND_FEEDBACK,
					N.SAVE_SETTINGS,
					N.GET_SETTINGS,
					N.EQUIP_ITEM,
				}
			do
				T.expect(RemoteGuard.RULES[name] ~= nil, "règle manquante : " .. name)
			end
		end)

		T.it("accepte les appels de notre client", function()
			local char, part = Instance.new("Model"), Instance.new("Part")
			T.expectEqual(honest(N.MELEE_DAMAGE, char, "primary", 1234.5), "ok")
			T.expectEqual(honest(N.MELEE_DAMAGE, char, "secondary", 1234.5), "ok")
			local shot = { Vector3.new(0, 5, 0), Vector3.new(1, 0, 0), Vector3.new(80, 5, 0), 1234.5 }
			T.expectEqual(honest(N.HITSCAN_DAMAGE, char, part, table.unpack(shot)), "ok")
			T.expectEqual(honest(N.SHOT_FIRED, Vector3.new(0, 5, 0), Vector3.new(1, 0, 0), 1234.5), "ok")
			T.expectEqual(honest(N.CHARACTER_SYNC, Vector3.new(10, -500, 3), 3.1, 0, false), "ok")
			T.expectEqual(honest(N.CHARACTER_SYNC, Vector3.new(10, -500, 3), 3.1, 0, true), "ok", "accroupi")
			T.expectEqual(honest(N.WEAPON_ACTION, "Shoot"), "ok")
			T.expectEqual(honest(N.WEAPON_ACTION, "Reload"), "ok")
			T.expectEqual(honest(N.REQUEST_SPAWN), "ok")
			T.expectEqual(honest(N.LEAVE_ROUND), "ok")
			T.expectEqual(honest(N.SEND_FEEDBACK, string.rep("é", 250)), "ok", "500 octets, la limite du client")
			T.expectEqual(honest(N.SAVE_SETTINGS, { sensitivity = 0.5 }), "ok")
			T.expectEqual(honest(N.GET_SETTINGS), "ok")
			T.expectEqual(honest(N.EQUIP_ITEM, "knife", "weapon.m9bayonet", ""), "ok", "skin d'origine")
			T.expectEqual(honest(N.EQUIP_ITEM, "sniper", "weapon.awp", "skin.awp.dragon_lore"), "ok")
		end)

		T.it("refuse un équipement d'une forme impossible (#280)", function()
			T.expectEqual(honest(N.EQUIP_ITEM, "pistol", "weapon.awp", ""), "malformed", "emplacement inconnu")
			T.expectEqual(honest(N.EQUIP_ITEM, "knife", 42, ""), "malformed", "id non textuel")
			T.expectEqual(honest(N.EQUIP_ITEM, "knife", "weapon.kabar"), "malformed", 'skin absent ("" attendu)')
			T.expectEqual(honest(N.EQUIP_ITEM, "knife", string.rep("a", 200), ""), "malformed", "id trop long")
		end)

		T.it("ignore sans violation un personnage propre au client (ragdoll local)", function()
			T.expectEqual(honest(N.HITSCAN_DAMAGE, nil, nil, Vector3.zero, Vector3.xAxis, Vector3.xAxis, 0), "missing")
			T.expectEqual(honest(N.MELEE_DAMAGE, nil, "primary"), "missing")
		end)

		T.it("refuse les types impossibles", function()
			T.expectEqual(honest(N.MELEE_DAMAGE, Instance.new("Model"), "backstab"), "malformed")
			T.expectEqual(honest(N.HITSCAN_DAMAGE, "Head", Instance.new("Part")), "malformed")
			local char, part = Instance.new("Model"), Instance.new("Part")
			T.expectEqual(honest(N.HITSCAN_DAMAGE, char, part), "malformed", "tir sans origine (ancien client)")
			T.expectEqual(
				honest(N.HITSCAN_DAMAGE, char, part, Vector3.zero, Vector3.new(0 / 0, 0, 0), Vector3.xAxis, 0),
				"malformed",
				"direction NaN"
			)
			T.expectEqual(
				honest(N.HITSCAN_DAMAGE, char, part, Vector3.zero, Vector3.xAxis, Vector3.xAxis, math.huge),
				"malformed",
				"instant infini"
			)
			T.expectEqual(honest(N.CHARACTER_SYNC, Vector3.new(0 / 0, 0, 0), 0, 0, false), "malformed")
			T.expectEqual(honest(N.CHARACTER_SYNC, Vector3.zero, nil, 0, false), "malformed")
			T.expectEqual(
				honest(N.CHARACTER_SYNC, Vector3.zero, 0, nil, false),
				"malformed",
				"numéro de correction absent"
			)
			T.expectEqual(honest(N.CHARACTER_SYNC, Vector3.zero, 0, 0), "malformed", "accroupi absent (ancien client)")
			T.expectEqual(honest(N.CHARACTER_SYNC, Vector3.zero, 0, 0, 1), "malformed", "accroupi non booléen")
			local target = Instance.new("Model")
			T.expectEqual(honest(N.MELEE_DAMAGE, target, "primary"), "malformed", "coup sans instant (ancien client)")
			T.expectEqual(honest(N.MELEE_DAMAGE, target, "primary", 0 / 0), "malformed", "instant NaN")
			T.expectEqual(honest(N.WEAPON_ACTION, "Equip"), "malformed")
			T.expectEqual(honest(N.SEND_FEEDBACK, string.rep("a", RemoteGuard.FEEDBACK_MAX_BYTES + 1)), "malformed")
			T.expectEqual(honest(N.SAVE_SETTINGS, "réglages"), "malformed")
			T.expectEqual(honest("RemoteInconnu"), "norule", "règle oubliée : bug du serveur, pas une triche")
		end)

		T.it("tient la cadence d'un client honnête sans refus", function()
			-- Position à 20 Hz pendant 10 s, avec un paquet de 2 s arrivé d'un coup après une coupure réseau
			local guard = RemoteGuard.new()
			local refused = 0
			for i = 0, 199 do
				if guard:check("joueur", N.CHARACTER_SYNC, i / 20, Vector3.zero, 0, 0, false) ~= "ok" then
					refused += 1
				end
			end
			for _ = 1, 40 do
				if guard:check("joueur", N.CHARACTER_SYNC, 12, Vector3.zero, 0, 0, false) ~= "ok" then
					refused += 1
				end
			end
			T.expectEqual(refused, 0, "position")
			-- Couteau au clic gauche (0,4 s) avec WeaponAction à chaque coup, deux coups arrivés groupés
			for i = 0, 49 do
				local t = i * 0.4 + (if i % 2 == 1 then -0.39 else 0)
				T.expectEqual(guard:check("joueur", N.MELEE_DAMAGE, t, Instance.new("Model"), "primary", t), "ok")
				T.expectEqual(guard:check("joueur", N.WEAPON_ACTION, t, "Shoot"), "ok")
			end
		end)

		T.it("refuse un flood et sépare joueurs et remotes", function()
			local guard = RemoteGuard.new()
			local burst = RemoteGuard.RULES[N.REQUEST_SPAWN].burst
			for _ = 1, burst do
				T.expectEqual(guard:check("a", N.REQUEST_SPAWN, 0), "ok")
			end
			T.expectEqual(guard:check("a", N.REQUEST_SPAWN, 0), "rate")
			T.expectEqual(guard:check("b", N.REQUEST_SPAWN, 0), "ok", "autre joueur")
			T.expectEqual(guard:check("a", N.WEAPON_ACTION, 0, "Shoot"), "ok", "autre remote")
			guard:forget("a")
			T.expectEqual(guard:check("a", N.REQUEST_SPAWN, 0), "ok", "seau neuf après le départ")
		end)

		T.it("ne vérifie pas les types d'un appel refusé pour débit", function()
			local guard = RemoteGuard.new()
			for _ = 1, RemoteGuard.RULES[N.WEAPON_ACTION].burst do
				guard:check("a", N.WEAPON_ACTION, 0, "Shoot")
			end
			T.expectEqual(guard:check("a", N.WEAPON_ACTION, 0, 42), "rate")
		end)
	end)
end
