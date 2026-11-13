-- Groupes de collision (#312) : le groupe des personnages est enregistré une fois et ne collisionne pas avec lui-même ;
-- toutes les pièces d'un personnage y sont rangées, y compris celles ajoutées après l'apparition (arme 3P, accessoires).
return function(T, Loader)
	-- Cette méthode permet de simuler PhysicsService lorsqu'un test enregistre le groupe : groupes enregistrés et paires
	-- non collidables notés pour les assertions.
	local function fakePhysics()
		local physics = { groups = {}, registerCalls = 0, collidable = {} }
		-- Cette méthode permet de dire si un groupe existe lorsque le module vérifie avant d'enregistrer.
		function physics.IsCollisionGroupRegistered(self, name)
			return self.groups[name] == true
		end
		-- Cette méthode permet de noter un enregistrement lorsque le module crée le groupe.
		function physics.RegisterCollisionGroup(self, name)
			self.registerCalls += 1
			self.groups[name] = true
		end
		-- Cette méthode permet de noter une paire collidable ou non lorsque le module la règle.
		function physics.CollisionGroupSetCollidable(self, a, b, value)
			assert(self.groups[a] and self.groups[b], "groupe non enregistré")
			self.collidable[a .. "|" .. b] = value
		end
		return physics
	end

	-- Cette méthode permet de simuler une instance lorsqu'un test construit un personnage : classe testée par IsA.
	local function fakeInstance(className: string)
		local inst = { ClassName = className, CollisionGroup = "Default" }
		-- Cette méthode permet de répondre au test de classe lorsque le module cherche les pièces (Part, MeshPart).
		function inst.IsA(self, name)
			local isPart = self.ClassName == "Part" or self.ClassName == "MeshPart"
			return name == "Instance" or name == self.ClassName or (name == "BasePart" and isPart)
		end
		return inst
	end

	-- Cette méthode permet de simuler un personnage lorsqu'un test range ses pièces : descendants fixés, `add` simule
	-- un DescendantAdded.
	local function fakeCharacter(descendants)
		local listeners = {}
		local char = {}
		-- Cette méthode permet de renvoyer les descendants fixés lorsque le module range le personnage.
		function char.GetDescendants()
			return descendants
		end
		char.DescendantAdded = {
			-- Cette méthode permet de retenir l'écoute lorsque le module se branche sur les ajouts.
			Connect = function(_, fn)
				table.insert(listeners, fn)
				return { Disconnect = function() end }
			end,
		}
		-- Cette méthode permet de simuler l'arrivée d'une instance lorsque le test ajoute une pièce après l'apparition.
		function char.add(inst)
			for _, fn in listeners do
				fn(inst)
			end
		end
		return char
	end

	T.describe("CollisionGroups", function()
		T.it("enregistre le groupe des personnages une seule fois, non collidable avec lui-même", function()
			local physics = fakePhysics()
			local CollisionGroups = Loader.new({ PhysicsService = physics }):require("src/shared/CollisionGroups")
			CollisionGroups.register()
			CollisionGroups.register()
			T.expectEqual(physics.registerCalls, 1)
			T.expectEqual(physics.collidable["Characters|Characters"], false)
		end)

		T.it("range les pièces présentes et ajoutées ensuite, pas les autres instances", function()
			local CollisionGroups = Loader.new({}):require("src/shared/CollisionGroups")
			local body = fakeInstance("MeshPart")
			local humanoid = fakeInstance("Humanoid")
			local char = fakeCharacter({ body, humanoid })
			CollisionGroups.assignCharacter(char)
			T.expectEqual(body.CollisionGroup, "Characters")
			T.expectEqual(humanoid.CollisionGroup, "Default")

			local gunPart = fakeInstance("Part")
			local weld = fakeInstance("Weld")
			char.add(gunPart)
			char.add(weld)
			T.expectEqual(gunPart.CollisionGroup, "Characters")
			T.expectEqual(weld.CollisionGroup, "Default")
		end)

		T.it("fait ignorer les personnages à une requête de mouvement", function()
			local CollisionGroups = Loader.new({}):require("src/shared/CollisionGroups")
			local params = { CollisionGroup = "Default" }
			CollisionGroups.ignoreCharacters(params :: any)
			T.expectEqual(params.CollisionGroup, CollisionGroups.CHARACTERS)
			local overlap = { CollisionGroup = "Default" }
			CollisionGroups.ignoreCharactersOverlap(overlap :: any)
			T.expectEqual(overlap.CollisionGroup, CollisionGroups.CHARACTERS)
		end)

		-- Garde-fou : une requête de mouvement oubliée referait des personnages des obstacles, sans erreur visible.
		T.it("fait ignorer les personnages à chaque requête des modules de mouvement", function()
			local fs = require("@lune/fs")
			local files = {}
			for _, dir in { "src/shared/movement", "src/client/systems/movement" } do
				for _, name in fs.readDir(dir) do
					if string.match(name, "%.luau$") then
						table.insert(files, dir .. "/" .. name)
					end
				end
			end
			for _, path in files do
				local source = fs.readFile(path)
				-- Cette méthode permet de compter les occurrences d'un motif lorsque le test compare requêtes et filtres.
				local function count(pattern: string): number
					local _, n = string.gsub(source, pattern, "")
					return n
				end
				T.expectEqual(count("RaycastParams%.new%("), count("CollisionGroups%.ignoreCharacters%("), path)
				T.expectEqual(count("OverlapParams%.new%("), count("CollisionGroups%.ignoreCharactersOverlap%("), path)
			end
		end)
	end)
end
