-- Tenues du personnage de l'accueil du menu (#253), vu de face : rotation de chaque Motor6D (rig R15 du StarterCharacter)
-- et prise de l'arme dans la main droite (repère de la main, comme WeaponConfig.ThirdPerson.Grip).
-- Rifle (tenue M1 de tools/anim/poses3p/poses.js) : AWP en travers du torse, canon vers le haut à gauche du personnage.
-- Généré par `node tools/anim/poses3p/export_pose.js` : modifier poses.js puis régénérer, ne pas retoucher à la main.
-- La prise vaut pour l'AWP (échelle 3P 0,7) ; une autre arme à distance demanderait la sienne.
-- Melee (tenue M2) : bras droit détendu le long du corps, lame vers le bas ; prise du jeu (WeaponConfig), bras gauche libre.
local MenuPoses = {}

MenuPoses.Rifle = {
	Joints = {
		RightShoulder = CFrame.new(
			0,
			0,
			0,
			0.79142,
			0.5608,
			0.24323,
			-0.50321,
			0.82362,
			-0.26159,
			-0.34703,
			0.08463,
			0.93403
		),
		RightElbow = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.73731, -0.67555, 0, 0.67555, 0.73731),
		RightWrist = CFrame.identity,
		LeftShoulder = CFrame.new(
			0,
			0,
			0,
			0.62447,
			-0.32089,
			-0.71208,
			0.34488,
			0.9313,
			-0.11722,
			0.70078,
			-0.17238,
			0.69224
		),
		LeftElbow = CFrame.new(0, 0, 0, 1, 0, 0, 0, -0.10619, -0.99435, 0, 0.99435, -0.10619),
		LeftWrist = CFrame.identity,
	},
	Grip = CFrame.new(
		-0.90252,
		0.03554,
		-0.53499,
		-0.93782,
		-0.00736,
		0.34703,
		-0.26185,
		0.67131,
		-0.69338,
		-0.22786,
		-0.74114,
		-0.6315
	),
}

MenuPoses.Melee = {
	Joints = {
		RightShoulder = CFrame.new(0, 0, 0, 0.98481, -0.17365, 0, 0.16985, 0.96329, -0.20791, 0.0361, 0.20475, 0.97815),
		RightElbow = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.86603, -0.5, 0, 0.5, 0.86603),
		RightWrist = CFrame.identity,
	},
}

return MenuPoses
