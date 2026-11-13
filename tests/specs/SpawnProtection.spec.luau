-- Protection d'apparition (#288) : ForceField visible posé à l'apparition, retiré au bout du délai ou au premier tir.
return function(T, Loader)
	local GameConfig = Loader.new():require("src/shared/GameConfig")

	-- Cette méthode permet de construire un faux personnage dont les enfants se détruisent lorsqu'un test vérifie la
	-- pose ou le retrait de la protection.
	local function fakeCharacter(names: { string })
		local char = { children = {} }
		-- Cette méthode permet d'ajouter un enfant destructible au faux personnage lorsqu'il est créé ou parenté.
		function char.add(self, child)
			function child.Destroy(c)
				local index = table.find(self.children, c)
				if index then
					table.remove(self.children, index)
				end
			end
			table.insert(self.children, child)
		end
		for _, name in names do
			char:add({ Name = name })
		end
		function char.GetChildren(self)
			return table.clone(self.children)
		end
		return char
	end

	-- Cette méthode permet de charger SpawnProtection avec Instance.new et task.delay simulés lorsqu'un test vérifie
	-- protect ; les appels différés sont rangés dans env.delayed.
	local function setup()
		local env = { delayed = {} }
		local fakeInstance = {
			new = function(className: string)
				local field = { ClassName = className }
				return setmetatable(field, {
					__newindex = function(t, key, value)
						rawset(t, key, value)
						if key == "Parent" and value then
							value:add(t)
						end
					end,
				})
			end,
		}
		env.Protection = Loader.new({}, {
			Instance = fakeInstance,
			task = {
				delay = function(seconds: number, fn)
					table.insert(env.delayed, { seconds = seconds, fn = fn })
				end,
			},
		}):require("src/server/SpawnProtection")
		return env
	end

	T.describe("SpawnProtection.protect", function()
		T.it("pose un ForceField visible, retiré au bout de SPAWN_PROTECTION", function()
			local env = setup()
			local char = fakeCharacter({ "Humanoid" })
			env.Protection.protect(char :: any)
			T.expectEqual(#char.children, 2)
			local field = char.children[2]
			T.expectEqual(field.ClassName, "ForceField")
			T.expectEqual(field.Name, env.Protection.NAME)
			T.expectEqual(field.Visible, true, "visible des autres joueurs")
			T.expectEqual(#env.delayed, 1)
			T.expectEqual(env.delayed[1].seconds, GameConfig.SPAWN_PROTECTION)
			env.delayed[1].fn()
			T.expectEqual(#char.children, 1, "délai écoulé : protection retirée")
		end)

		T.it("dure 2 s (décision de #288)", function()
			T.expectEqual(GameConfig.SPAWN_PROTECTION, 2)
		end)

		T.it("posée puis retirée au premier tir, le délai ne fait plus rien", function()
			local env = setup()
			local char = fakeCharacter({})
			env.Protection.protect(char :: any)
			T.expectEqual(env.Protection.drop(char :: any), true)
			T.expectEqual(#char.children, 0)
			env.delayed[1].fn()
			T.expectEqual(#char.children, 0)
		end)
	end)

	T.describe("SpawnProtection.drop", function()
		local Protection = Loader.new():require("src/server/SpawnProtection")

		T.it("retire la protection au premier tir, puis plus rien", function()
			local char = fakeCharacter({ Protection.NAME, "Humanoid" })
			T.expectEqual(Protection.drop(char :: any), true)
			T.expectEqual(#char.children, 1)
			T.expectEqual(char.children[1].Name, "Humanoid")
			T.expectEqual(Protection.drop(char :: any), false, "second tir : plus de protection")
		end)

		T.it("ne retire pas un autre ForceField", function()
			local char = fakeCharacter({ "ForceField" })
			T.expectEqual(Protection.drop(char :: any), false)
			T.expectEqual(#char.children, 1)
		end)

		T.it("sans personnage : rien", function()
			T.expectEqual(Protection.drop(nil), false)
		end)
	end)
end
