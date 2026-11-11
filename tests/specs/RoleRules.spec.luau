-- Attribution des rôles (#266) : propriétaire, liste d'UserId, inconnu, rôle inconnu.
return function(T, Loader)
	local RoleRules = Loader.new():require("src/server/RoleRules")
	local CREATOR = 100
	local LISTS = { Admin = { 7 }, Modo = { 8, 7 } }

	T.describe("RoleRules.assign", function()
		T.it("donne Admin au propriétaire du jeu", function()
			T.expectEqual(RoleRules.has(RoleRules.assign(CREATOR, CREATOR, LISTS), "Admin"), true)
		end)

		T.it("ne donne aucun rôle à un inconnu", function()
			T.expectEqual(next(RoleRules.assign(55, CREATOR, LISTS)), nil)
		end)

		T.it("donne le rôle d'une liste à son UserId", function()
			local roles = RoleRules.assign(8, CREATOR, LISTS)
			T.expectEqual(RoleRules.has(roles, "Modo"), true)
			T.expectEqual(RoleRules.has(roles, "Admin"), false)
		end)

		T.it("cumule les rôles d'un UserId présent dans plusieurs listes", function()
			local roles = RoleRules.assign(7, CREATOR, LISTS)
			T.expectEqual(RoleRules.has(roles, "Admin"), true)
			T.expectEqual(RoleRules.has(roles, "Modo"), true)
		end)

		T.it("ne fait pas d'un CreatorId à 0 (place non publiée) un Admin", function()
			T.expectEqual(RoleRules.has(RoleRules.assign(0, 0, LISTS), "Admin"), false)
		end)
	end)

	T.describe("RoleRules.has", function()
		T.it("renvoie false pour un rôle inconnu", function()
			T.expectEqual(RoleRules.has(RoleRules.assign(CREATOR, CREATOR, LISTS), "Fantome"), false)
		end)

		T.it("renvoie false sans rôles", function()
			T.expectEqual(RoleRules.has(nil, "Admin"), false)
		end)
	end)

	T.describe("RoleRules.display", function()
		T.it("choisit le premier rôle de l'ordre, ou une chaîne vide", function()
			T.expectEqual(RoleRules.display({ Modo = true, Admin = true }, { "Admin", "Modo" }), "Admin")
			T.expectEqual(RoleRules.display({}, { "Admin" }), "")
		end)
	end)
end
