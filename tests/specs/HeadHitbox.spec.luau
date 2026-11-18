-- HeadHitbox.fitted : boîte de la tête ramenée à la tête affichée (#539), affichage et hauteur vue par le mouvement
-- inchangés.
return function(T, Loader)
	local HeadHitbox = Loader.new({}):require("src/shared/HeadHitbox")

	-- Tête du StarterCharacter relevée dans Studio le 18/11/2026
	local RIG_SIZE = Vector3.new(3.1763904, 1.5881952, 1.5881952)
	local RIG_SCALE = Vector3.new(1.25, 1.25, 1.25)

	T.describe("HeadHitbox", function()
		T.it("donne à la boîte la taille de la tête affichée, plus étroite que les épaules", function()
			local size = HeadHitbox.fitted(RIG_SIZE, RIG_SCALE, HeadHitbox.SIZE)
			for _, axis in { "X", "Y", "Z" } do
				T.expectNear(size[axis], HeadHitbox.SIZE, 1e-4, "boîte " .. axis)
			end
			T.expect(size.X < RIG_SIZE.X * 0.65, "la boîte ne doit plus avoir la largeur des épaules")
			-- Tête affichée mesurée : 1,91 × 1,93 × 1,91
			T.expect(HeadHitbox.SIZE >= 1.9 and HeadHitbox.SIZE <= 1.95, "taille hors de la tête mesurée")
		end)

		T.it("garde la tête affichée : plus petite dimension × échelle inchangée", function()
			local size, scale = HeadHitbox.fitted(RIG_SIZE, RIG_SCALE, HeadHitbox.SIZE)
			local before = math.min(RIG_SIZE.X, RIG_SIZE.Y, RIG_SIZE.Z) * RIG_SCALE.X
			local after = math.min(size.X, size.Y, size.Z) * scale.X
			T.expectNear(after, before, 1e-4, "tête affichée")
		end)

		T.it("garde la hauteur de tête lue par CharacterDimensions (max de la boîte et du mesh)", function()
			local size, scale = HeadHitbox.fitted(RIG_SIZE, RIG_SCALE, HeadHitbox.SIZE)
			local before = math.max(RIG_SIZE.Y, RIG_SIZE.Y * RIG_SCALE.Y)
			local after = math.max(size.Y, size.Y * scale.Y)
			T.expectNear(after, before, 1e-4, "hauteur de tête")
		end)
	end)
end
