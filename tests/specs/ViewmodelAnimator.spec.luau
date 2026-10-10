return function(T, Loader)
	local loader = Loader.new()
	local Animator = loader:require("src/client/systems/weapon/ViewmodelAnimator")

	-- Cette méthode permet de comparer deux positions lorsqu'un test vérifie un déplacement.
	local function expectVec(actual, expected, message)
		T.expectNear(actual.X, expected.X, 1e-3, message .. " (X)")
		T.expectNear(actual.Y, expected.Y, 1e-3, message .. " (Y)")
		T.expectNear(actual.Z, expected.Z, 1e-3, message .. " (Z)")
	end

	-- Cette méthode permet de construire un set minimal (Idle + une action à marqueurs) lorsqu'un test joue des clips.
	local function makeClips()
		return Animator.compileSet({
			Clips = {
				Idle = { Length = 2, Looped = true, Tracks = { A = { { t = 1, p = { 0, 1, 0 } } } } },
				Act = {
					Length = 1,
					Tracks = { A = { { t = 0.5, p = { 2, 0, 0 } } } },
					Markers = {
						{ t = 0, name = "Start" },
						{ t = 0.4, name = "Mid" },
						{ t = 1, name = "End" },
					},
				},
			},
		}).clips
	end

	T.describe("ViewmodelAnimator.compileClip", function()
		T.it("ajoute la pose de repos au début et à la fin de chaque piste", function()
			local clip = Animator.compileClip("X", { Length = 1, Tracks = { A = { { t = 0.5, p = { 1, 0, 0 } } } } })
			local keys = clip.tracks.A
			T.expectEqual(#keys, 3)
			T.expectEqual(keys[1].t, 0)
			T.expectEqual(keys[3].t, 1)
			expectVec(Animator.sampleTrack(keys, 0).Position, Vector3.zero, "début")
			expectVec(Animator.sampleTrack(keys, 1).Position, Vector3.zero, "fin")
			expectVec(Animator.sampleTrack(keys, 0.5).Position, Vector3.new(1, 0, 0), "milieu")
		end)

		T.it("refuse un easing inconnu ou une keyframe hors du clip", function()
			T.expect(
				not pcall(Animator.compileClip, "X", { Length = 1, Tracks = { A = { { t = 0.5, e = "bounce" } } } })
			)
			T.expect(not pcall(Animator.compileClip, "X", { Length = 1, Tracks = { A = { { t = 2 } } } }))
		end)
	end)

	T.describe("ViewmodelAnimator.sampleTrack", function()
		T.it("interpole les angles composante par composante (rotation de 360°)", function()
			local clip = Animator.compileClip("X", {
				Length = 1,
				Tracks = { A = { { t = 0 }, { t = 1, r = { 360, 0, 0 }, e = "linear" } } },
			})
			-- À mi-parcours la pièce est retournée (180°), ce qu'un Lerp de CFrame ne ferait pas
			local mid = Animator.sampleTrack(clip.tracks.A, 0.5)
			T.expectNear(mid.UpVector.Y, -1, 1e-3, "retournée à 180°")
			local quarter = Animator.sampleTrack(clip.tracks.A, 0.25)
			T.expectNear(quarter.UpVector.Z, 1, 1e-3, "90° autour de X")
		end)
	end)

	T.describe("ViewmodelAnimator lecture", function()
		T.it("étire l'action sur la durée demandée puis revient à l'idle", function()
			local anim = Animator.new(makeClips())
			anim:play("Act", 2)
			anim:step(1.9)
			T.expectEqual(anim:getAction(), "Act", "encore en cours à 1,9 s")
			anim:step(0.2)
			T.expectEqual(anim:getAction(), nil, "terminée après 2 s")
		end)

		T.it("déclenche chaque marqueur une seule fois et dans l'ordre, même avec de grands pas", function()
			local anim = Animator.new(makeClips())
			anim:play("Act")
			local all = {}
			for _ = 1, 4 do
				local _, fired = anim:step(0.3)
				for _, name in fired do
					table.insert(all, name)
				end
			end
			T.expectEqual(table.concat(all, ","), "Start,Mid,End")
		end)

		T.it("un marqueur à t = 0 part dès la première frame", function()
			local anim = Animator.new(makeClips())
			anim:play("Act")
			local _, fired = anim:step(1 / 60)
			T.expectEqual(fired[1], "Start")
		end)

		T.it("fond l'entrée d'une action au lieu de sauter de pose", function()
			local anim = Animator.new(makeClips())
			anim:step(1) -- idle au sommet : A.Y = 1
			anim:play("Act", nil)
			local pose = anim:step(0.04) -- moitié du fondu d'entrée par défaut
			local y = pose.A.Position.Y
			T.expect(y > 0.2 and y < 0.9, "fondu en cours (Y = " .. y .. ")")
		end)

		T.it("reset coupe l'action sans fondu", function()
			local anim = Animator.new(makeClips())
			anim:play("Act")
			anim:step(0.5)
			anim:reset()
			T.expectEqual(anim:getAction(), nil)
			local pose = anim:step(0)
			expectVec(pose.A.Position, Vector3.zero, "idle à t = 0")
		end)

		T.it("ne lance pas l'Idle comme une action", function()
			local anim = Animator.new(makeClips())
			T.expectEqual(anim:play("Idle"), false)
			T.expectEqual(anim:play("Inconnu"), false)
		end)
	end)

	T.describe("ViewmodelAnimator.resolveDeltas", function()
		T.it("tourne autour du pivot sans le déplacer", function()
			local rig = Animator.compileRig({ Pivots = { A = Vector3.new(1, 2, 3) } })
			local deltas = Animator.resolveDeltas({ A = CFrame.Angles(0.3, 1.1, -0.4) }, rig)
			expectVec(deltas.A * Vector3.new(1, 2, 3), Vector3.new(1, 2, 3), "pivot fixe")
		end)

		T.it("fait suivre une articulation par une autre et applique la pose de base", function()
			local rig = Animator.compileRig({
				Follow = { Arm = "Gun" },
				Base = { Arm = { p = { 0, -1, 0 } } },
			})
			local deltas = Animator.resolveDeltas({ Gun = CFrame.new(2, 0, 0) }, rig)
			expectVec(deltas.Arm.Position, Vector3.new(2, -1, 0), "arme + base")
		end)

		T.it("toTransform reproduit le décalage dans le repère du Part0", function()
			local c0 = CFrame.new(1, -0.5, -3) * CFrame.Angles(0, -math.pi / 2, 0)
			local delta = CFrame.new(0.2, 0.3, 0) * CFrame.Angles(0.1, 0, 0.2)
			local transform = Animator.toTransform(delta, c0)
			local viaMotor = c0 * transform
			local expected = delta * c0
			expectVec(viaMotor.Position, expected.Position, "position")
			expectVec(viaMotor.LookVector, expected.LookVector, "orientation")
		end)
	end)
end
