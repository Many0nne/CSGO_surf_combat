-- Garde d'achat commune (#545) : verrou « un achat en vol par joueur » (`busy`), `failed` + `warn` sur erreur avec verrou
-- rendu, branchement du remote (`rate` avant tout achat, `onBought` avant la réponse). CheatLog est remplacé par un
-- double (tests/lib/CheatLogStub.luau) : seule la garde est testée ici.
return function(T, Loader)
	-- Cette méthode permet de monter PurchaseRemote avec un CheatLog simulé lorsqu'un test démarre.
	local function setup()
		local real = Loader.new().game:GetService("ServerScriptService")
		local server = setmetatable({}, {
			__index = function(_, name)
				if name == "CheatLog" then
					return { __path = "tests/lib/CheatLogStub" }
				end
				return real.Server[name]
			end,
		})
		local env = { warns = {} }
		local loader = Loader.new({ ServerScriptService = { Server = server } }, {
			warn = function(...)
				table.insert(env.warns, table.concat({ ... }, " "))
			end,
		})
		env.PurchaseRemote = loader:require("src/server/PurchaseRemote")
		env.cheat = loader:require("tests/lib/CheatLogStub")
		return env
	end

	-- Cette méthode permet de construire une réponse de refus lorsque la garde ou l'achat refuse.
	local function refuse(reason: string)
		return { ok = false, reason = reason }
	end

	local player = { Name = "Alice" }

	T.describe("PurchaseRemote.guard", function()
		T.it("renvoie la réponse de l'achat et rend le verrou", function()
			local env = setup()
			local calls = 0
			local buy = env.PurchaseRemote.guard("Test", refuse, function(_, arg)
				calls += 1
				return { ok = true, arg = arg }
			end)
			T.expectEqual(buy(player, "a").arg, "a")
			T.expectEqual(buy(player, "b").arg, "b")
			T.expectEqual(calls, 2)
		end)

		T.it("refuse `busy` pendant un achat en vol, sans lancer un second achat", function()
			local env = setup()
			local calls = 0
			local inner
			local buy
			buy = env.PurchaseRemote.guard("Test", refuse, function()
				calls += 1
				inner = buy(player, "x")
				return { ok = true }
			end)
			local result = buy(player, "x")
			T.expectEqual(result.ok, true)
			T.expectEqual(inner.reason, "busy")
			T.expectEqual(calls, 1)
		end)

		T.it("le verrou est par joueur : un autre joueur n'est pas `busy`", function()
			local env = setup()
			local other = { Name = "Bob" }
			local inner
			local buy
			buy = env.PurchaseRemote.guard("Test", refuse, function(p)
				if p == player then
					inner = buy(other, "x")
				end
				return { ok = true }
			end)
			buy(player, "x")
			T.expectEqual(inner.ok, true)
		end)

		T.it("une erreur d'achat donne `failed`, un `warn` préfixé, et rend le verrou", function()
			local env = setup()
			local fail = true
			local buy = env.PurchaseRemote.guard("Test", refuse, function()
				if fail then
					error("boum")
				end
				return { ok = true }
			end)
			T.expectEqual(buy(player, "x").reason, "failed")
			T.expectEqual(#env.warns, 1)
			T.expect(string.find(env.warns[1], "[Test]", 1, true) ~= nil, "préfixe du service : " .. env.warns[1])
			fail = false
			T.expectEqual(buy(player, "x").ok, true)
		end)
	end)

	T.describe("PurchaseRemote.connect", function()
		-- Cette méthode permet de créer un faux RemoteFunction lorsqu'un test branche `connect`.
		local function remote()
			return { Name = "BuyThing" }
		end

		T.it("garde refusée : `rate`, ni achat ni `onBought`", function()
			local env = setup()
			env.cheat.admitted = false
			local bought, notified = 0, 0
			local r = remote()
			env.PurchaseRemote.connect(r, refuse, function()
				bought += 1
				return { ok = true }
			end, function()
				notified += 1
			end)
			T.expectEqual(r.OnServerInvoke(player, "x").reason, "rate")
			T.expectEqual(bought, 0)
			T.expectEqual(notified, 0)
			T.expectEqual(env.cheat.lastRemote, "BuyThing")
		end)

		T.it("achat traité : `onBought` reçoit joueur, argument et réponse avant le retour au client", function()
			local env = setup()
			local order = {}
			local r = remote()
			env.PurchaseRemote.connect(r, refuse, function(_, arg)
				table.insert(order, "buy")
				return { ok = true, arg = arg }
			end, function(p, arg, result)
				table.insert(order, "onBought")
				T.expectEqual(p, player)
				T.expectEqual(arg, "x")
				T.expectEqual(result.arg, "x")
			end)
			local result = r.OnServerInvoke(player, "x")
			T.expectEqual(result.ok, true)
			T.expectEqual(table.concat(order, ","), "buy,onBought")
		end)

		T.it("sans `onBought` : la réponse part quand même", function()
			local env = setup()
			local r = remote()
			env.PurchaseRemote.connect(r, refuse, function()
				return { ok = true }
			end, nil)
			T.expectEqual(r.OnServerInvoke(player, "x").ok, true)
		end)
	end)
end
