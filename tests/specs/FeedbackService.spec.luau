-- Feedback (#171) : limite en mémoire avant tout accès DataStore quel que soit le résultat, quota hebdomadaire jamais
-- écrasé après une lecture échouée.
return function(T, Loader)
	local WEEK = 7 * 24 * 3600

	-- Cette méthode permet de monter FeedbackService avec DataStore, webhook, horloge et remotes simulés lorsqu'un
	-- test démarre ; env.store compte les accès (UpdateAsync) et les écritures, env.acks garde les réponses au client.
	local function setup(opts: { webhook: boolean?, postOk: boolean?, readFails: boolean?, stored: any? }?)
		local o = opts or {}
		local env = { time = 1000000, acks = {}, posts = 0, warns = {}, delayed = {}, online = false }
		env.store = { gets = 0, sets = {}, data = o.stored, readFails = o.readFails == true }
		function env.store.UpdateAsync(self, _key, transform)
			self.gets += 1
			if self.readFails then
				error("DataStore indisponible")
			end
			local value = transform(if type(self.data) == "table" then table.clone(self.data) else self.data)
			if value ~= nil then
				table.insert(self.sets, value)
				self.data = value
			end
		end
		local server = setmetatable({}, {
			__index = function(_, name)
				return { __path = "src/server/" .. name }
			end,
		})
		local loader = Loader.new({
			Players = {
				GetPlayerByUserId = function()
					return if env.online then env.player else nil
				end,
				PlayerRemoving = {
					Connect = function(_, fn)
						env.onRemoving = fn
					end,
				},
			},
			RunService = {
				IsStudio = function()
					return true
				end,
			},
			DataStoreService = {
				GetDataStore = function()
					return env.store
				end,
			},
			ServerScriptService = {
				Server = server,
				FindFirstChild = function(_, name)
					if name == "FeedbackWebhookUrl" and o.webhook ~= false then
						return {
							Value = "https://example.invalid/hook",
							IsA = function(_, class)
								return class == "StringValue"
							end,
						}
					end
					return nil
				end,
			},
			HttpService = {
				JSONEncode = function()
					return "{}"
				end,
				PostAsync = function()
					env.posts += 1
					if o.postOk == false then
						error("HTTP 500")
					end
				end,
			},
		}, {
			os = {
				clock = function()
					return env.time
				end,
				time = function()
					return env.time
				end,
				date = os.date,
			},
			warn = function(...)
				table.insert(env.warns, table.concat({ ... }, " "))
			end,
			task = {
				spawn = function() end,
				delay = function(_seconds, fn)
					table.insert(env.delayed, fn)
				end,
			},
		})
		env.FeedbackService = loader:require("src/server/FeedbackService")
		local send = {
			OnServerEvent = {
				Connect = function(_, fn)
					env.handler = fn
				end,
			},
		}
		local ack = {
			FireClient = function(_, _player, ok, message)
				table.insert(env.acks, { ok = ok, message = message })
			end,
		}
		env.FeedbackService.init(send :: any, ack :: any)
		env.player = { UserId = 7, Name = "Alice", Parent = {} }
		-- Cette méthode permet d'envoyer un feedback valide lorsqu'un test simule une demande du client.
		function env.send(text: string?)
			env.handler(env.player, text or "Un retour assez long pour passer.")
			return env.acks[#env.acks]
		end
		return env
	end

	T.describe("FeedbackService.weeklyQuota", function()
		local env = setup()
		local quota = env.FeedbackService.weeklyQuota

		T.it("ajoute now aux envois des 7 derniers jours et ignore les valeurs forgées", function()
			local now = WEEK * 3
			local verdict, list = quota({ now - WEEK - 1, now - 10, "x" }, now)
			T.expectEqual(verdict, "ok")
			T.expectEqual(#list, 2)
			T.expectEqual(list[2], now)
		end)

		T.it("refuse à la limite de 5 par semaine", function()
			local now = WEEK * 3
			T.expectEqual(quota({ now - 1, now - 2, now - 3, now - 4, now - 5 }, now), "overLimit")
			T.expectEqual(quota(nil, now), "ok", "première lecture : clé absente")
		end)
	end)

	T.describe("FeedbackService : limite en mémoire avant le DataStore", function()
		T.it("envoi réussi : une lecture, une écriture, puis plus d'accès pendant le délai", function()
			local env = setup()
			T.expectEqual(env.send().ok, true)
			T.expectEqual(env.store.gets, 1)
			T.expectEqual(#env.store.sets, 1)
			env.time += 5
			T.expectEqual(env.send().ok, false)
			T.expectEqual(env.store.gets, 1, "pas de lecture pendant le délai")
		end)

		T.it("échec du webhook : délai posé quand même, envoi rendu au quota", function()
			local env = setup({ postOk = false, stored = { 999990 } })
			T.expectEqual(env.send().message, "Erreur lors de l'envoi.")
			T.expectEqual(#env.store.data, 1, "l'envoi en échec ne compte pas dans la semaine")
			T.expectEqual(env.store.data[1], 999990)
			local accesses = env.store.gets
			env.time += 5
			env.send()
			T.expectEqual(env.posts, 1)
			T.expectEqual(env.store.gets, accesses, "pas d'accès pendant le délai")
		end)

		T.it("reconnexion pendant le délai : délai conservé", function()
			local env = setup()
			env.send()
			env.time += 5
			env.onRemoving(env.player)
			env.player = { UserId = 7, Name = "Alice", Parent = {} }
			T.expectEqual(env.send().ok, false)
			T.expectEqual(env.store.gets, 1)
		end)

		T.it("oublie le délai d'un joueur parti une fois écoulé", function()
			local env = setup()
			env.send()
			env.onRemoving(env.player)
			T.expectEqual(#env.delayed, 1)
			env.delayed[1]()
			env.time += 1
			T.expectEqual(env.send().ok, true, "plus de délai en mémoire")
		end)

		T.it("pas de webhook : ni DataStore ni quota consommé, délai posé", function()
			local env = setup({ webhook = false })
			T.expectEqual(env.send().message, "Système indisponible.")
			env.time += 5
			env.send()
			T.expectEqual(env.store.gets, 0)
			T.expectEqual(#env.store.sets, 0)
		end)

		T.it("quota atteint : une seule lecture par délai, pas d'écriture", function()
			local now = 1000000
			local env = setup({ stored = { now - 1, now - 2, now - 3, now - 4, now - 5 } })
			T.expectEqual(env.send().ok, false)
			for _ = 1, 2 do
				env.time += 10
				env.send()
			end
			T.expectEqual(env.store.gets, 1)
			T.expectEqual(#env.store.sets, 0)
			env.time += 60
			env.send()
			T.expectEqual(env.store.gets, 2, "nouvelle lecture après le délai")
		end)

		T.it("lecture échouée : refus sans écriture du quota ni envoi", function()
			local env = setup({ readFails = true, stored = { 999999 } })
			local ack = env.send()
			T.expectEqual(ack.ok, false)
			T.expectEqual(#env.store.sets, 0, "le quota existant n'est pas écrasé")
			T.expectEqual(env.posts, 0)
			T.expectEqual(env.store.data[1], 999999)
		end)

		T.it("message trop court : refusé sans toucher au délai ni au DataStore", function()
			local env = setup()
			env.send("court")
			T.expectEqual(env.store.gets, 0)
			env.time += 3
			T.expectEqual(env.send().ok, true, "le délai ne part pas d'un message invalide")
		end)
	end)
end
