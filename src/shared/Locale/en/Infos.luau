-- Traductions anglaises (#518, cf. Locale) : texte français affiché -> texte anglais.
-- Écran Infos (COMMANDES, CRÉDITS, À PROPOS), légendes de la démo d'Apprendre et conseils de l'écran de mort : les
-- gabarits `{nom}` reçoivent les touches du joueur.
return {
	-- Sections
	["COMMANDES"] = "CONTROLS",
	["À PROPOS"] = "ABOUT",

	-- COMMANDES : une ligne par action
	["SOURIS {n}"] = "MOUSE {n}",
	["Se déplacer"] = "Move",
	["Sauter / bhop (auto-bhop réglable dans Réglages)"] = "Jump / bhop (auto-bhop adjustable in Settings)",
	["S'accroupir"] = "Crouch",
	["Marche lente"] = "Slow walk",
	["Tirer"] = "Fire",
	["Viser avec la lunette / estoc au couteau"] = "Aim down the scope / knife stab",
	["Recharger"] = "Reload",
	["Inspecter l'arme"] = "Inspect weapon",
	["Changer d'arme"] = "Switch weapon",
	["Changer d'arme (réglable dans Réglages)"] = "Switch weapon (adjustable in Settings)",
	["Classement"] = "Scoreboard",
	["Menu en partie (réglages, retour au menu)"] = "In-game menu (settings, back to menu)",

	-- CRÉDITS
	["Physique inspirée du Source SDK (surf de CS:GO)."] = "Physics inspired by the Source SDK (CS:GO surf).",

	-- À PROPOS
	["Envie de donner ton avis ou de filer un coup de main ? Rejoins le Discord : discord.gg/ZwWrnVG2ar"] = "Want to share your thoughts or lend a hand? Join the Discord: discord.gg/ZwWrnVG2ar",

	-- Démo de l'écran Apprendre
	["BHOP"] = "BHOP",
	["Garde {jump} (auto-bhop), puis en l'air {left} en tournant la souris à gauche, {right} à droite, sans {forward}."] = "Hold {jump} (auto-bhop), then in the air hold {left} while turning the mouse left, {right} to the right, without {forward}.",
	["Appuie sur {jump} à chaque atterrissage (démo en auto-bhop), puis en l'air {left} en tournant la souris à gauche, {right} à droite, sans {forward}."] = "Press {jump} on every landing (demo uses auto-bhop), then in the air hold {left} while turning the mouse left, {right} to the right, without {forward}.",

	-- Conseils de l'écran de mort
	["AIR STRAFE"] = "AIR STRAFE",
	["maintiens {left} ou {right} contre la rampe, ne touche jamais à {forward}."] = "hold {left} or {right} against the ramp, never touch {forward}.",
	["garde {jump} enfoncé, tu ressautes dès que tu touches le sol. Démo : APPRENDRE."] = "keep {jump} held and you jump again as soon as you touch the ground. Demo: LEARN.",
	["appuie sur {jump} à chaque fois que tu touches le sol. Démo : APPRENDRE."] = "press {jump} every time you touch the ground. Demo: LEARN.",
	["en l'air, tiens {left} en tournant la souris à gauche, {right} à droite. Démo : APPRENDRE."] = "in the air, hold {left} while turning the mouse left, {right} to the right. Demo: LEARN.",
}
