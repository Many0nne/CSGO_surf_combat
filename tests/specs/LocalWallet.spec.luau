-- LocalWallet (#446) : les écrans qui affichent le gain du jour (bandeau « PLAFOND DU JOUR ATTEINT », « GAINS DU JOUR »)
-- sont prévenus au changement de jour UTC, sans autre événement ; le gain du jour retombe à 0 après minuit.
return function(T, Loader)
	local DAY = 20000
	local MIDNIGHT = (DAY + 1) * 86400

	-- Cette méthode permet de construire un monde simulé (horloge serveur, minuterie, joueur) lorsqu'un test démarre ;
	-- `advance(s)` fait avancer l'horloge et réveille les `task.wait` échus.
	local function world(daily: string?)
		local now = MIDNIGHT - 60 -- 23:59 UTC
		local waiters = {}
		local attributes = { DailyCredits = daily }
		local signals = {}
		local player = {
			GetAttribute = function(_, name)
				return attributes[name]
			end,
			GetAttributeChangedSignal = function(_, name)
				signals[name] = signals[name] or {}
				return {
					Connect = function(_, fn)
						table.insert(signals[name], fn)
						return { Disconnect = function() end }
					end,
				}
			end,
		}
		local fakeTask = {
			-- Comme task.spawn : une erreur dans le fil lancé ne remonte pas à l'appelant
			spawn = function(fn, ...)
				coroutine.wrap(function(...)
					pcall(fn, ...)
				end)(...)
			end,
			wait = function(seconds)
				table.insert(waiters, { wake = now + seconds, thread = coroutine.running() })
				coroutine.yield()
			end,
		}
		local fakeWorkspace = {
			GetServerTimeNow = function()
				return now
			end,
		}
		local wallet = Loader.new(
			{ Players = { LocalPlayer = player } },
			{ task = fakeTask, workspace = fakeWorkspace }
		)
			:require("src/client/systems/inventory/LocalWallet")
		return {
			wallet = wallet,
			advance = function(seconds: number)
				now += seconds
				local due = {}
				for i = #waiters, 1, -1 do
					if waiters[i].wake <= now then
						table.insert(due, 1, table.remove(waiters, i))
					end
				end
				for _, waiter in due do
					coroutine.resume(waiter.thread)
				end
			end,
		}
	end

	T.describe("LocalWallet : changement de jour UTC", function()
		T.it("prévient l'abonné après minuit UTC et remet le gain du jour à 0", function()
			local w = world(DAY .. ":250")
			local seen = {}
			w.wallet.observeDaily(function()
				table.insert(seen, w.wallet.dailyEarned())
			end)
			T.expectEqual(#seen, 1)
			T.expectEqual(seen[1], 250)
			w.advance(30) -- 23:59:30 : pas encore minuit
			T.expectEqual(#seen, 1)
			w.advance(31) -- 00:00:01 : minuit passé, marge comprise
			T.expectEqual(#seen, 2)
			T.expectEqual(seen[2], 0)
		end)

		T.it("prévient tous les abonnés avec une seule minuterie, jour après jour", function()
			local w = world(DAY .. ":250")
			local a, b = 0, 0
			w.wallet.observeDaily(function()
				a += 1
			end)
			w.wallet.observeDaily(function()
				b += 1
			end)
			w.advance(61)
			T.expectEqual(a, 2)
			T.expectEqual(b, 2)
			w.advance(86400)
			T.expectEqual(a, 3)
			T.expectEqual(b, 3)
		end)

		T.it("ne prévient plus un abonné désabonné", function()
			local w = world(DAY .. ":250")
			local count = 0
			local unobserve = w.wallet.observeDaily(function()
				count += 1
			end)
			unobserve()
			w.advance(61)
			T.expectEqual(count, 1)
		end)

		T.it("un abonné qui échoue n'empêche ni les autres ni les jours suivants", function()
			local w = world(DAY .. ":250")
			local good = 0
			local first = true
			w.wallet.observeDaily(function()
				if not first then
					error("abonné cassé")
				end
				first = false
			end)
			w.wallet.observeDaily(function()
				good += 1
			end)
			w.advance(61)
			w.advance(86400)
			T.expectEqual(good, 3)
		end)

		T.it("la même fonction abonnée deux fois : un désabonnement ne coupe pas l'autre", function()
			local w = world(DAY .. ":250")
			local count = 0
			local function paint()
				count += 1
			end
			local unobserveA = w.wallet.observeDaily(paint)
			w.wallet.observeDaily(paint)
			T.expectEqual(count, 2)
			unobserveA()
			w.advance(61)
			T.expectEqual(count, 3)
		end)

		T.it("la minuterie s'arrête sans abonné et repart à l'abonnement suivant", function()
			local w = world(DAY .. ":250")
			local count = 0
			local unobserve = w.wallet.observeDaily(function()
				count += 1
			end)
			unobserve()
			w.advance(61) -- le fil se réveille, ne trouve personne et s'arrête
			w.advance(86400)
			T.expectEqual(count, 1)
			w.wallet.observeDaily(function()
				count += 1
			end)
			T.expectEqual(count, 2)
			w.advance(86400)
			T.expectEqual(count, 3)
		end)

		T.it("gain du jour nil tant que l'attribut n'est pas chargé", function()
			local w = world(nil)
			T.expectEqual(w.wallet.dailyEarned(), nil)
		end)
	end)
end
