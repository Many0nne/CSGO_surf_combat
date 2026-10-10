-- clips/AWP.luau
-- Animations du viewmodel AWP écrites en code (#19), lues par ViewmodelAnimator.
-- Pistes nommées d'après la pièce animée (Part1 du Motor6D). p = décalage (studs), r = angles XYZ (degrés),
-- e = easing du segment qui arrive sur la keyframe. Repos implicite au début et à la fin de chaque piste.
-- Repères : Joint et bras dans le repère caméra (X droite, Y haut, -Z avant) ; pièces de l'arme dans le repère
-- du Handle (+X vers la crosse, +Y haut, -Z côté droit, où se trouve le levier de culasse).
-- Marqueurs : un marqueur "X" joue le son X du dossier Sounds du viewmodel (cf. WeaponConfig.AnimationSounds).

-- Cycle de culasse réutilisé par le tir, l'equip et la recharge : main droite vers le levier, levée, recul,
-- retour, rabattement, main qui revient sur la poignée. t0 = début du cycle.
local function boltCycle(t0: number)
	return {
		Bolt_Handle = {
			{ t = t0 + 0.15 },
			{ t = t0 + 0.24, r = { 70, 0, 0 }, e = "out" },
			{ t = t0 + 0.36, p = { 0.85, 0, 0 }, r = { 70, 0, 0 }, e = "out" },
			{ t = t0 + 0.44, p = { 0.85, 0, 0 }, r = { 70, 0, 0 } },
			{ t = t0 + 0.54, r = { 70, 0, 0 }, e = "in" },
			{ t = t0 + 0.62, e = "out" },
		},
		Bolt = {
			{ t = t0 + 0.24 },
			{ t = t0 + 0.36, p = { 0.85, 0, 0 }, e = "out" },
			{ t = t0 + 0.44, p = { 0.85, 0, 0 } },
			{ t = t0 + 0.54, e = "in" },
		},
		RightUpperArm = {
			{ t = t0 },
			{ t = t0 + 0.15, p = { 0.2, 0.55, -0.5 }, r = { 0, 0, 15 }, e = "outCubic" },
			{ t = t0 + 0.24, p = { 0.15, 0.75, -0.5 }, r = { 0, 0, 25 }, e = "out" },
			{ t = t0 + 0.36, p = { 0.15, 0.75, 0.35 }, r = { 0, 0, 25 }, e = "out" },
			{ t = t0 + 0.44, p = { 0.15, 0.75, 0.35 }, r = { 0, 0, 25 } },
			{ t = t0 + 0.54, p = { 0.15, 0.75, -0.5 }, r = { 0, 0, 25 }, e = "in" },
			{ t = t0 + 0.62, p = { 0.2, 0.55, -0.5 }, r = { 0, 0, 15 }, e = "out" },
			{ t = t0 + 0.82, e = "sine" },
		},
	}
end

-- Cette méthode permet de fusionner les pistes du cycle de culasse dans celles d'un clip lorsqu'un clip en a besoin ;
-- les pistes communes sont concaténées (les keyframes sont triées à la compilation).
local function withBolt(tracks, t0: number)
	for joint, keys in boltCycle(t0) do
		local merged = tracks[joint] or {}
		for _, k in keys do
			table.insert(merged, k)
		end
		tracks[joint] = merged
	end
	return tracks
end

return {
	Rig = {
		Pivots = {
			Joint = Vector3.new(1.1, -0.85, -1.6), -- poignée
			RightUpperArm = Vector3.new(1.34, -1.31, -1.52), -- main droite
			LeftUpperArm = Vector3.new(1.04, -1.34, -4.04), -- main gauche
			Bolt_Handle = Vector3.new(1.51, 0.48, 0), -- axe de la culasse (repère Handle)
			Magazine = Vector3.new(1.28, 0.06, 0),
		},
		-- Les bras restent collés à l'arme : leurs décalages propres s'ajoutent à celui de l'arme
		Follow = {
			RightUpperArm = "Joint",
			LeftUpperArm = "Joint",
		},
	},

	Clips = {
		Idle = {
			Length = 4,
			Looped = true,
			Tracks = {
				Joint = {
					{ t = 2, p = { 0, 0.02, 0.015 }, r = { 0.7, 0, 0.4 } },
				},
				LeftUpperArm = {
					{ t = 2.4, p = { 0, 0.01, 0.02 }, r = { 0, 0, 1 } },
				},
			},
		},

		Equip = {
			Length = 1.58,
			BlendIn = 0,
			Tracks = withBolt({
				Joint = {
					{ t = 0, p = { 0.4, -2.4, 1.2 }, r = { -40, 15, -30 } },
					{ t = 0.42, p = { 0, 0.08, 0.05 }, r = { 4, 0, -2 }, e = "outCubic" },
					{ t = 0.55, r = { 0, 0, 4 } },
					{ t = 1.2, p = { 0, 0.05, 0 }, r = { 2, 0, 10 } },
					{ t = 1.58, e = "sine" },
				},
			}, 0.5),
			Markers = {
				{ t = 0, name = "Draw" },
				{ t = 0.74, name = "Bolt" },
			},
		},

		Shoot = {
			Length = 1.63,
			BlendIn = 0.02,
			Tracks = withBolt({
				Joint = {
					{ t = 0.04, p = { 0, 0.08, 0.55 }, r = { 9, 0, -2 }, e = "out" },
					{ t = 0.28, p = { 0, 0.02, 0.12 }, r = { 2, 0, 0 } },
					{ t = 0.45, r = { 0, 0, 4 } },
					{ t = 1.1, p = { 0, 0.05, 0 }, r = { 2, 0, 10 } },
					{ t = 1.63, e = "sine" },
				},
				Trigger = {
					{ t = 0.02, p = { 0.04, 0, 0 }, e = "out" },
					{ t = 0.2 },
				},
			}, 0.4),
			Markers = {
				{ t = 0, name = "Shoot" },
				{ t = 0.64, name = "Bolt" },
			},
		},

		Reload = {
			Length = 3.7,
			Tracks = withBolt({
				Joint = {
					{ t = 0.3, p = { -0.15, -0.1, 0.1 }, r = { -4, 8, 16 } },
					{ t = 0.5, p = { -0.15, -0.05, 0.1 }, r = { -2, 8, 17 }, e = "out" },
					{ t = 2.3, p = { -0.15, -0.12, 0.1 }, r = { -5, 8, 16 } },
					{ t = 2.42, p = { -0.15, 0.02, 0.1 }, r = { -1, 8, 18 }, e = "out" },
					{ t = 2.75, p = { 0, 0.05, 0 }, r = { 2, 0, 10 } },
					{ t = 3.45, p = { 0, 0.05, 0 }, r = { 2, 0, 10 } },
					{ t = 3.7, e = "sine" },
				},
				LeftUpperArm = {
					{ t = 0.32, p = { 0.05, -0.1, 1.65 }, r = { 0, 0, -10 } },
					{ t = 0.45, p = { 0.05, 0, 1.65 }, r = { 0, 0, -10 }, e = "out" },
					{ t = 0.85, p = { 0.1, -1.6, 1.6 }, r = { -10, 0, -15 }, e = "inOut" },
					{ t = 1.15, p = { 0.4, -3.2, 1.3 }, r = { -25, 0, -20 }, e = "in" },
					{ t = 1.5, p = { 0.4, -3.2, 1.3 }, r = { -25, 0, -20 } },
					{ t = 1.95, p = { 0.05, -1.0, 1.65 }, r = { -8, 0, -12 }, e = "outCubic" },
					{ t = 2.32, p = { 0.05, -0.12, 1.65 }, r = { 0, 0, -10 }, e = "inOut" },
					{ t = 2.4, p = { 0.05, -0.02, 1.65 }, r = { 0, 0, -10 }, e = "out" },
					{ t = 2.52, p = { 0.05, 0.12, 1.65 }, r = { 3, 0, -10 }, e = "out" },
					{ t = 2.62, p = { 0.05, -0.05, 1.65 }, r = { 0, 0, -10 } },
					{ t = 3.0, e = "sine" },
				},
				Magazine = {
					{ t = 0.45 },
					{ t = 0.55, p = { 0, -0.15, 0 }, e = "out" },
					{ t = 0.85, p = { -0.05, -1.65, -0.05 }, r = { 0, 0, 10 }, e = "inOut" },
					{ t = 1.15, p = { -0.35, -3.3, -0.35 }, r = { 0, 0, 25 }, e = "in" },
					{ t = 1.5, p = { -0.35, -3.3, -0.35 }, r = { 0, 0, 25 } },
					{ t = 1.95, p = { 0, -1.05, -0.05 }, r = { 0, 0, 8 }, e = "outCubic" },
					{ t = 2.32, p = { 0, -0.12, 0 }, e = "inOut" },
					{ t = 2.4, e = "out" },
				},
			}, 2.62),
			Markers = {
				{ t = 0.45, name = "ClipOut" },
				{ t = 2.38, name = "ClipIn" },
				{ t = 2.52, name = "ClipHit" },
				{ t = 2.86, name = "Bolt" },
			},
		},

		Inspect = {
			Length = 4.6,
			BlendIn = 0.15,
			Tracks = {
				Joint = {
					{ t = 0.7, p = { -0.7, 0.3, 0.5 }, r = { 6, 38, 26 }, e = "inOut" },
					{ t = 1.9, p = { -0.75, 0.35, 0.5 }, r = { 9, 42, 30 } },
					{ t = 2.8, p = { -0.4, 0.15, 0.25 }, r = { -6, -28, -22 }, e = "inOut" },
					{ t = 3.8, p = { -0.42, 0.18, 0.25 }, r = { -8, -31, -24 } },
					{ t = 4.6, e = "inOut" },
				},
			},
		},
	},
}
