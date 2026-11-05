-- Retouches locales de Dizzy, appliquées dans l'ordre par build_dizzy.luau après le plan relevé (dizzy_layout.json) :
-- elles survivent à la régénération et à un nouveau relevé. C'est ici, et pas dans Studio ni dans le JSON, qu'on
-- corrige un détail de la map (procédure : docs/maps.md, « Corriger un détail de Dizzy »).
--
-- Coordonnées du monde, lues telles quelles dans Studio (propriété Position, décalage de 2000 en X compris).
-- Champs : tools/map/DizzyPatches.luau. Chaque retouche dit pourquoi elle existe (`why`) ; une zone vide est une erreur.
--
-- Exemples :
--   -- Mur d'air qui bloque le saut vers le balcon nord (signalé le 12/11)
--   { op = "remove", why = "mur d'air du balcon nord", folder = "Clips",
--     zone = { center = { 1880, 45, -300 }, size = { 10, 20, 10 } } },
--
--   -- Fente visible au coin de l'escalier CT
--   { op = "add", why = "fente escalier CT", look = "wall",
--     position = { 2130, 78, -126 }, size = { 2, 8, 2 } },
--
--   -- Caisse de couverture au milieu du toit, tournée de 30°
--   { op = "add", why = "couvert au centre", look = "decor:metal",
--     position = { 2000, 4, -250 }, size = { 8, 8, 8 }, rotation = { 0, 30, 0 } },
--
--   -- Murs trop clairs dans la salle T
--   { op = "restyle", why = "murs salle T", folder = "Walls", look = "ceiling",
--     zone = { center = { 1820, 50, -100 }, size = { 60, 40, 60 } } },

return {
	-- Rampes sur pilotis (côté CT puis côté T) : charpente en bois, plateau en contreplaqué. `group` épargne les sacs
	-- (stucco) posés sous la rampe CT.
	{ op = "restyle", why = "charpente de la rampe CT", folder = "Decor", group = "metal", look = "timber",
		zone = { center = { 2113.54, 55.56, -389.89 }, size = { 91.93, 27.4, 112.25 } } },
	{ op = "restyle", why = "plateau de la rampe CT", folder = "Decor", look = "plywood",
		zone = { center = { 2113.8, 56.4, -390.1 }, size = { 1, 0.6, 1 } } },
	{ op = "restyle", why = "charpente de la rampe T", folder = "Decor", group = "metal", look = "timber",
		zone = { center = { 1886.46, 55.56, -130.3 }, size = { 91.93, 27.4, 112.25 } } },
	{ op = "restyle", why = "plateau de la rampe T", folder = "Decor", look = "plywood",
		zone = { center = { 1886.2, 56.4, -130.0 }, size = { 1, 0.6, 1 } } },

	-- Planches posées sur la fosse centrale (passerelles), sans les poutres d'acier qui les portent. Jamais de restyle
	-- sans `folder` sur une zone qui touche un mur d'air : il deviendrait visible.
	{ op = "restyle", why = "planche est de la fosse", folder = "Decor", look = "planks",
		zone = { center = { 2026, 71.375, -260.1 }, size = { 14.4, 0.5, 2 } } },
	{ op = "restyle", why = "planche ouest de la fosse (dessus)", folder = "Floors", look = "planks",
		zone = { center = { 1973.6, 71.65, -260 }, size = { 16.2, 0.5, 132 } } },
	{ op = "restyle", why = "planche ouest de la fosse (rives)", folder = "Walls", look = "planks",
		zone = { center = { 1973.6, 71.65, -260 }, size = { 16.2, 0.5, 132 } } },
	{ op = "restyle", why = "rives de la planche ouest", folder = "Decor", look = "planks",
		zone = { center = { 1973.5, 71.15, -260.1 }, size = { 14, 0.1, 2 } } },

	-- Extracteurs d'air des estrades d'angle relevés en boîtes tournées : remplacés par les extracteurs de DizzyDressing
	{ op = "remove", why = "extracteurs de l'estrade T", folder = "Decor",
		zone = { center = { 1769.37, 52.9, -50.8 }, size = { 23, 16, 1 } } },
	{ op = "remove", why = "extracteurs de l'estrade CT", folder = "Decor",
		zone = { center = { 2230.63, 52.9, -469.4 }, size = { 23, 16, 1 } } },

	-- Caissons de climatisation relevés en boîtes empilées : remplacés par les groupes détaillés de DizzyDressing
	{ op = "remove", why = "caisson balcon nord gauche", folder = "Decor",
		zone = { center = { 1967.46, 56.89, 20.31 }, size = { 3.94, 18.73, 17.44 } } },
	{ op = "remove", why = "caisson balcon nord droit", folder = "Decor",
		zone = { center = { 2048.74, 56.89, 20.33 }, size = { 3.8, 18.73, 17.47 } } },
	{ op = "remove", why = "caisson balcon sud droit", folder = "Decor",
		zone = { center = { 2032.54, 56.89, -540.5 }, size = { 3.94, 18.73, 17.44 } } },
	{ op = "remove", why = "caisson balcon sud gauche", folder = "Decor",
		zone = { center = { 1951.26, 56.89, -540.53 }, size = { 3.8, 18.73, 17.47 } } },
	{ op = "remove", why = "caisson du toit haut CT", folder = "Decor",
		zone = { center = { 2077.22, 112.41, -290.58 }, size = { 17.76, 13.14, 0.73 } } },
	{ op = "remove", why = "caisson du toit haut T", folder = "Decor",
		zone = { center = { 1922.79, 112.41, -229.62 }, size = { 17.76, 13.14, 0.73 } } },
}
