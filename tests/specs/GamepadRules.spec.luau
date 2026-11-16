-- Sticks analogiques (#276) : stick gauche → axes de déplacement, stick droit → vitesse de rotation de la caméra.
return function(T, Loader)
	local GamepadRules = Loader.new():require("src/shared/GamepadRules")

	T.describe("GamepadRules.moveAxes", function()
		T.it("reste au repos dans la zone morte", function()
			local f, r = GamepadRules.moveAxes(0.1, 0.15)
			T.expectEqual(f, 0)
			T.expectEqual(r, 0)
		end)

		T.it("donne les quatre directions pures, stick à fond ou à moitié", function()
			local cases = {
				{ x = 0, y = 1, f = 1, r = 0 },
				{ x = 0, y = -0.5, f = -1, r = 0 },
				{ x = 1, y = 0, f = 0, r = 1 },
				{ x = -0.6, y = 0, f = 0, r = -1 },
			}
			for _, c in cases do
				local f, r = GamepadRules.moveAxes(c.x, c.y)
				T.expectEqual(f, c.f, `({c.x}, {c.y}) avant`)
				T.expectEqual(r, c.r, `({c.x}, {c.y}) droite`)
			end
		end)

		T.it("aimante sur le côté pur près de l'axe (air strafe sans avancer)", function()
			-- 15° au-dessus de l'axe droit
			local a = math.rad(15)
			local f, r = GamepadRules.moveAxes(math.cos(a), math.sin(a))
			T.expectEqual(f, 0)
			T.expectEqual(r, 1)
		end)

		T.it("garde une direction libre et normalisée loin des axes", function()
			local f, r = GamepadRules.moveAxes(0.5, 0.5)
			T.expectNear(f, math.sqrt(0.5), 1e-6)
			T.expectNear(r, math.sqrt(0.5), 1e-6)
			local f2, r2 = GamepadRules.moveAxes(-0.5, 0.8)
			T.expectNear(f2 * f2 + r2 * r2, 1, 1e-6)
			T.expectEqual(f2 > 0 and r2 < 0, true)
		end)
	end)

	T.describe("GamepadRules.lookRate", function()
		T.it("ne tourne pas dans la zone morte", function()
			local x, y = GamepadRules.lookRate(0.1, -0.05)
			T.expectEqual(x, 0)
			T.expectEqual(y, 0)
		end)

		T.it("tourne à pleine vitesse stick à fond", function()
			local x, y = GamepadRules.lookRate(1, 0)
			T.expectNear(x, 1, 1e-6)
			T.expectNear(y, 0, 1e-6)
		end)

		T.it("suit une courbe : à mi-course, moins de la moitié de la vitesse", function()
			local x = GamepadRules.lookRate(0.575, 0)
			T.expectEqual(x > 0 and x < 0.5, true, tostring(x))
			T.expectNear(x, 0.25, 1e-6)
		end)

		T.it("garde la direction du stick", function()
			local x, y = GamepadRules.lookRate(-0.6, 0.8)
			T.expectNear(y / x, 0.8 / -0.6, 1e-6)
			T.expectEqual(x < 0 and y > 0, true)
		end)
	end)
end
