return function(T, Loader)
	local EquipRules = Loader.new({}):require("src/client/systems/weapon/EquipRules")

	T.describe("EquipRules.lockTime (#404)", function()
		T.it("reprend EquipTime de la config, sans regarder la piste Equip", function()
			T.expectEqual(EquipRules.lockTime({ EquipTime = 1.267 }), 1.267)
			T.expectEqual(EquipRules.lockTime({ EquipTime = 1, EquipAnimSpeed = 1.3 }), 1, "vitesse de piste ignorée")
			T.expectEqual(EquipRules.lockTime({ EquipTime = 0 }), 0)
		end)

		T.it("retombe sur le verrou par défaut sans config ou sans EquipTime valide", function()
			T.expectEqual(EquipRules.lockTime(nil), EquipRules.DEFAULT_EQUIP_TIME)
			T.expectEqual(EquipRules.lockTime({}), EquipRules.DEFAULT_EQUIP_TIME)
			T.expectEqual(EquipRules.lockTime({ EquipTime = -1 }), EquipRules.DEFAULT_EQUIP_TIME)
		end)
	end)

	T.describe("EquipRules.newGate", function()
		T.it("garde courant le jeton du dernier equip", function()
			local gate = EquipRules.newGate()
			local token = gate.begin()
			T.expect(gate.isCurrent(token))
		end)

		T.it("périme le délai d'un equip précédent de la même arme (changement puis retour rapide)", function()
			local gate = EquipRules.newGate()
			local first = gate.begin()
			gate.invalidate() -- rangée
			local second = gate.begin() -- rééquipée aussitôt
			T.expect(not gate.isCurrent(first), "le premier délai ne doit pas finir le second equip")
			T.expect(gate.isCurrent(second))
		end)

		T.it("périme aussi un equip enchaîné sans rangement", function()
			local gate = EquipRules.newGate()
			local first = gate.begin()
			local second = gate.begin()
			T.expect(not gate.isCurrent(first))
			T.expect(gate.isCurrent(second))
		end)

		T.it("périme le jeton quand l'arme est rangée", function()
			local gate = EquipRules.newGate()
			local token = gate.begin()
			gate.invalidate()
			T.expect(not gate.isCurrent(token))
		end)

		T.it(
			"périme le délai de tir, de coup ou de rechargement lancé avant un changement d'arme rapide (#183)",
			function()
				local gate = EquipRules.newGate()
				local fire = gate.begin() -- tir
				gate.invalidate() -- arme rangée
				local equip = gate.begin() -- arme reprise aussitôt
				T.expect(not gate.isCurrent(fire), "l'ancien délai ne doit pas remettre IDLE pendant l'equip")
				T.expect(gate.isCurrent(equip))
			end
		)

		T.it("laisse le délai d'une action non interrompue s'appliquer", function()
			local gate = EquipRules.newGate()
			local reload = gate.begin()
			T.expect(gate.isCurrent(reload))
		end)
	end)
end
