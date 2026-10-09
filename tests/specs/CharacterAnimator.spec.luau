return function(T, Loader)
	local loader = Loader.new()
	local CharacterAnimator = loader:require("src/shared/CharacterAnimator")
	local Config = loader:require("src/shared/CharacterConfig")

	-- Cette méthode permet de construire une entrée d'animation au sol par défaut lorsqu'un test n'en surcharge qu'une partie.
	local function input(over)
		local base = { onGround = true, crouching = false, surfing = false, speed = 0, verticalSpeed = 0 }
		for k, v in over or {} do
			base[k] = v
		end
		return base
	end

	T.describe("CharacterAnimator.resolveState", function()
		T.it("idle à l'arrêt, marche puis course selon la vitesse", function()
			T.expectEqual(CharacterAnimator.resolveState(input()), "IDLE")
			T.expectEqual(CharacterAnimator.resolveState(input({ speed = Config.WALK_SPEED_MAX })), "WALK")
			T.expectEqual(CharacterAnimator.resolveState(input({ speed = Config.WALK_SPEED_MAX + 1 })), "RUN")
		end)

		T.it("en l'air : saut en montée, chute en descente", function()
			T.expectEqual(CharacterAnimator.resolveState(input({ onGround = false, verticalSpeed = 20 })), "JUMP")
			T.expectEqual(CharacterAnimator.resolveState(input({ onGround = false, verticalSpeed = -5 })), "FALL")
		end)

		T.it("accroupi : idle ou marche accroupie au sol, pose aérienne en l'air", function()
			T.expectEqual(CharacterAnimator.resolveState(input({ crouching = true })), "CROUCH_IDLE")
			T.expectEqual(CharacterAnimator.resolveState(input({ crouching = true, speed = 8 })), "CROUCH_WALK")
			T.expectEqual(
				CharacterAnimator.resolveState(input({ crouching = true, onGround = false, verticalSpeed = -1 })),
				"FALL"
			)
		end)

		T.it("le surf prime sur l'état aérien", function()
			T.expectEqual(
				CharacterAnimator.resolveState(input({ onGround = false, surfing = true, speed = 80 })),
				"SURF"
			)
		end)
	end)

	T.describe("CharacterAnimator.resolveAnimationId", function()
		T.it("chaque état produit un id (fallback si non renseigné)", function()
			for _, state in { "IDLE", "WALK", "RUN", "JUMP", "FALL", "CROUCH_IDLE", "CROUCH_WALK", "SURF" } do
				local id = CharacterAnimator.resolveAnimationId(state)
				T.expect(type(id) == "string" and id ~= "", "pas d'animation pour " .. state)
			end
		end)

		T.it("une entrée vide retombe sur son FALLBACK", function()
			if Config.ANIMATIONS.SURF == "" then
				T.expectEqual(
					CharacterAnimator.resolveAnimationId("SURF"),
					CharacterAnimator.resolveAnimationId(Config.FALLBACK.SURF)
				)
			end
		end)
	end)

	T.describe("CharacterAnimator.playbackSpeed", function()
		T.it("proportionnelle à la vitesse et bornée", function()
			T.expectNear(CharacterAnimator.playbackSpeed("RUN", Config.REF_SPEED.RUN), 1)
			T.expectNear(CharacterAnimator.playbackSpeed("RUN", 1000), Config.PLAYBACK_MAX)
			T.expectNear(CharacterAnimator.playbackSpeed("WALK", 0.1), Config.PLAYBACK_MIN)
		end)

		T.it("vaut 1 pour les états sans cycle de pas", function()
			T.expectEqual(CharacterAnimator.playbackSpeed("FALL", 50), 1)
		end)
	end)
end
