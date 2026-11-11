return function(T, Loader)
	local EquipRules = Loader.new({}):require("src/client/systems/weapon/EquipRules")

	T.describe("EquipRules.duration", function()
		T.it("divise la longueur de la piste par la vitesse", function()
			T.expectNear(EquipRules.duration(1.5, 1.5, 0.8), 1, 1e-9)
		end)

		T.it("retombe sur la durée de la config sans piste ou sans vitesse valide", function()
			T.expectEqual(EquipRules.duration(0, 1, 0.8), 0.8)
			T.expectEqual(EquipRules.duration(1.2, 0, 0.8), 0.8)
		end)
	end)

	T.describe("EquipRules.animSpeed", function()
		T.it("renvoie la vitesse de la config lorsqu'elle est valide", function()
			T.expectEqual(EquipRules.animSpeed(1.3), 1.3)
		end)

		T.it("retombe sur 1 sans vitesse, à 0 ou négative", function()
			T.expectEqual(EquipRules.animSpeed(nil), 1)
			T.expectEqual(EquipRules.animSpeed(0), 1)
			T.expectEqual(EquipRules.animSpeed(-2), 1)
		end)
	end)

	T.describe("EquipRules.settleTime (#184)", function()
		local TIMEOUT = EquipRules.LOAD_TIMEOUT

		T.it("donne longueur / vitesse dès que la piste est chargée", function()
			T.expectNear(EquipRules.settleTime(1, 1.3, 0.77, 0, TIMEOUT) :: number, 1 / 1.3, 1e-9)
		end)

		T.it("ne retombe pas sur EquipTime quand la piste est chargée après un temps d'attente", function()
			T.expectNear(EquipRules.settleTime(1.58, nil, 0.5, 0.8, TIMEOUT) :: number, 1.58, 1e-9)
		end)

		T.it("attend (nil) tant que la piste n'est pas chargée et que le délai n'est pas écoulé", function()
			T.expectEqual(EquipRules.settleTime(0, 1.3, 0.77, 0, TIMEOUT), nil)
			T.expectEqual(EquipRules.settleTime(0, 1.3, 0.77, TIMEOUT - 0.01, TIMEOUT), nil)
		end)

		T.it(
			"retombe sur EquipTime dès le départ pour une arme sans piste Equip (nil), sans attendre le délai",
			function()
				T.expectEqual(EquipRules.settleTime(nil, 1.3, 0.77, 0, TIMEOUT), 0.77)
			end
		)

		T.it("ne cumule pas l'attente et EquipTime : le repli tient compte du temps déjà attendu", function()
			T.expectEqual(EquipRules.settleTime(nil, nil, 0.8, 0.3, TIMEOUT), 0.5)
			T.expectEqual(EquipRules.settleTime(0, 1.3, 0.77, TIMEOUT, TIMEOUT), 0) -- 2 s attendues > EquipTime
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
