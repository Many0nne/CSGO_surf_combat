return function(T, Loader)
	local ScopeSensitivity = Loader.new({}):require("src/shared/ScopeSensitivity")

	T.describe("ScopeSensitivity", function()
		T.it("donne un ratio de 1 sans zoom", function()
			T.expectNear(ScopeSensitivity.zoomRatio(90, 90), 1, 1e-9)
		end)

		T.it("donne le ratio tan(fov/2) / tan(90/2) des deux zooms de l'AWP", function()
			T.expectNear(ScopeSensitivity.zoomRatio(40, 90), 0.36397, 1e-4, "zoom 1 (FOV 40)")
			T.expectNear(ScopeSensitivity.zoomRatio(10, 90), 0.08749, 1e-4, "zoom 2 (FOV 10)")
		end)

		T.it("garde la sensi de base hors lunette, quel que soit le multiplicateur", function()
			T.expectEqual(ScopeSensitivity.effective(0.1, nil, 90, 1.7), 0.1)
		end)

		T.it("combine sensi de base × ratio du zoom × multiplicateur à la lunette", function()
			local ratio = ScopeSensitivity.zoomRatio(40, 90)
			T.expectNear(ScopeSensitivity.effective(0.1, 40, 90, 1), 0.1 * ratio, 1e-9, "multiplicateur 1")
			T.expectNear(ScopeSensitivity.effective(0.1, 40, 90, 2), 0.2 * ratio, 1e-9, "multiplicateur 2")
			T.expect(ScopeSensitivity.effective(0.1, 10, 90, 1) < ScopeSensitivity.effective(0.1, 40, 90, 1))
		end)
	end)
end
