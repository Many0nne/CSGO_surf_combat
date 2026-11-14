-- Corps entier d'un personnage côté client (#328) : la réplication annonce le personnage avant toutes ses pièces ;
-- CharacterAppearance.waitForParts attend celles du rig de référence (StarterCharacter), délai borné.
return function(T, Loader)
	T.describe("CharacterAppearance.waitForParts", function()
		-- Cette méthode permet de simuler un enfant lorsqu'un test construit un rig ou un personnage.
		local function child(name, className)
			return {
				Name = name,
				ClassName = className,
				-- Cette méthode permet de répondre au test de classe lorsque le module trie les pièces.
				IsA = function(self, c)
					return c == self.ClassName or (c == "BasePart" and self.ClassName == "MeshPart")
				end,
			}
		end

		-- Cette méthode permet de simuler un modèle lorsqu'un test fixe ses enfants présents et ceux qui arrivent
		-- pendant l'attente (`late` : reçus par WaitForChild), les autres n'arrivant jamais.
		local function model(present, late)
			local m = { waited = {} }
			-- Cette méthode permet de se présenter comme un Model lorsque le module valide le rig de référence.
			function m.IsA(_, c)
				return c == "Model"
			end
			-- Cette méthode permet de lister les enfants lorsque le module lit le rig de référence.
			function m.GetChildren()
				return present
			end
			-- Cette méthode permet de trouver un enfant déjà présent lorsque le module vérifie le personnage.
			function m.FindFirstChild(_, name)
				for _, c in present do
					if c.Name == name then
						return c
					end
				end
				return nil
			end
			-- Cette méthode permet de simuler l'attente d'un enfant lorsque le module attend une pièce absente.
			function m.WaitForChild(_, name, timeout)
				table.insert(m.waited, { name = name, timeout = timeout })
				return if late and late[name] then child(name, "MeshPart") else nil
			end
			return m
		end

		local template = model({
			child("HumanoidRootPart", "MeshPart"),
			child("Humanoid", "Humanoid"),
			child("LeftFoot", "MeshPart"),
			child("RightFoot", "MeshPart"),
		})
		local starterPlayer = {
			-- Cette méthode permet de rendre le rig de référence lorsque le module cherche StarterCharacter.
			FindFirstChild = function(_, name)
				return if name == "StarterCharacter" then template else nil
			end,
		}
		local CharacterAppearance = Loader.new({ StarterPlayer = starterPlayer })
			:require("src/shared/CharacterAppearance")

		T.it("liste les pièces du rig, pas ses autres enfants", function()
			local names = CharacterAppearance.partNames(template)
			T.expectEqual(table.concat(names, ","), "HumanoidRootPart,LeftFoot,RightFoot")
		end)

		T.it("n'attend rien quand le personnage est complet", function()
			local char = model({
				child("HumanoidRootPart", "MeshPart"),
				child("LeftFoot", "MeshPart"),
				child("RightFoot", "MeshPart"),
			})
			T.expectEqual(#CharacterAppearance.waitForParts(char, 5), 0)
			T.expectEqual(#char.waited, 0)
		end)

		T.it("attend les jambes encore absentes et rend celles qui ne sont jamais arrivées", function()
			local char = model({ child("HumanoidRootPart", "MeshPart") }, { LeftFoot = true })
			local missing = CharacterAppearance.waitForParts(char, 5)
			T.expectEqual(table.concat(missing, ","), "RightFoot")
			T.expectEqual(#char.waited, 2)
			T.expect(char.waited[1].timeout > 0 and char.waited[1].timeout <= 5, "attente bornée par le délai")
		end)
	end)
end
