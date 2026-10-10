-- clips/Butterfly.luau
-- Animations du viewmodel couteau papillon écrites en code (#19), lues par ViewmodelAnimator.
-- Le manche principal (Handle) est soudé à la main droite ; la lame (Blade) pivote sur le manche et le second
-- manche (Bite) pivote sur la lame. Rotation des ouvertures autour de l'axe X (épaisseur du couteau).
-- Bras dans le repère caméra (X droite, Y haut, -Z avant) ; Blade dans le repère du Handle ; Bite dans celui de Blade.
-- Marqueur "Stab" : résolu dynamiquement par WeaponSystem (raycast + son Shoot_void/human/wall).

return {
	Rig = {
		Pivots = {
			RightUpperArm = Vector3.new(2.87, -0.88, -2.52), -- main droite
			LeftUpperArm = Vector3.new(-1.38, -1.13, -2.31), -- main gauche
			Blade = Vector3.new(0, 0, 0.75), -- goupille du manche principal (repère Handle)
			Bite = Vector3.new(0, -0.09, -0.72), -- goupille du second manche (repère Blade)
		},
		-- Main gauche baissée hors champ : le couteau se tient à une main
		Base = {
			LeftUpperArm = { p = { -0.9, -2.6, 0.9 }, r = { -30, 0, 20 } },
		},
	},

	Clips = {
		Idle = {
			Length = 3.5,
			Looped = true,
			Tracks = {
				RightUpperArm = {
					{ t = 1.75, p = { 0, 0.025, 0.01 }, r = { 1, 0, -1 } },
				},
			},
		},

		Equip = {
			Length = 1.0,
			BlendIn = 0,
			Tracks = {
				RightUpperArm = {
					{ t = 0, p = { 0.4, -2.2, 0.8 }, r = { -35, 0, 25 } },
					{ t = 0.32, p = { 0, 0.06, 0 }, r = { 4, 0, -3 }, e = "outCubic" },
					{ t = 0.5, r = { 0, 0, 0 } },
				},
				Blade = {
					{ t = 0, r = { 180, 0, 0 } },
					{ t = 0.12, r = { 180, 0, 0 } },
					{ t = 0.42, e = "out" },
				},
				Bite = {
					{ t = 0, r = { -180, 0, 0 } },
					{ t = 0.2, r = { -180, 0, 0 } },
					{ t = 0.5, e = "out" },
				},
			},
			Markers = {
				{ t = 0, name = "Equip" },
			},
		},

		Shoot = {
			Length = 1.0,
			BlendIn = 0.03,
			Tracks = {
				RightUpperArm = {
					{ t = 0.1, p = { 0.35, 0.25, 0.3 }, r = { 10, -25, -30 }, e = "out" },
					{ t = 0.24, p = { -1.2, -0.1, -0.6 }, r = { -10, 45, 40 }, e = "outCubic" },
					{ t = 0.45, p = { -0.9, -0.3, -0.3 }, r = { -5, 30, 25 } },
					{ t = 0.85, e = "sine" },
				},
			},
			Markers = {
				{ t = 0.2, name = "Stab" },
			},
		},

		Inspect = {
			Length = 3.2,
			BlendIn = 0.15,
			Tracks = {
				RightUpperArm = {
					{ t = 0.4, p = { -0.6, 0.3, -0.2 }, r = { 10, 30, 40 }, e = "inOut" },
					{ t = 2.6, p = { -0.65, 0.32, -0.2 }, r = { 12, 34, 44 } },
					{ t = 3.2, e = "inOut" },
				},
				Blade = {
					{ t = 0.6 },
					{ t = 0.85, r = { 180, 0, 0 }, e = "inOut" },
					{ t = 1.15, r = { 0, 0, 0 }, e = "inOut" },
					{ t = 1.55 },
					{ t = 1.8, r = { 180, 0, 0 }, e = "inOut" },
					{ t = 2.1, r = { 0, 0, 0 }, e = "inOut" },
				},
				Bite = {
					{ t = 0.65 },
					{ t = 0.9, r = { -180, 0, 0 }, e = "inOut" },
					{ t = 1.2, r = { 0, 0, 0 }, e = "inOut" },
					{ t = 1.6 },
					{ t = 1.85, r = { -180, 0, 0 }, e = "inOut" },
					{ t = 2.15, r = { 0, 0, 0 }, e = "inOut" },
				},
			},
			Markers = {
				{ t = 0.6, name = "Equip" },
				{ t = 1.55, name = "Equip" },
			},
		},
	},
}
