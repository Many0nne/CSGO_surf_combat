-- Traductions anglaises (#518, cf. Locale) : texte français affiché -> texte anglais.
-- Menu principal, menu en partie, démo de l'écran Apprendre, transition, feedback et écran de chargement.
return {
	-- Menu principal
	["SURF FFA"] = "SURF FFA",
	["COMBAT DE SURF"] = "SURF COMBAT",
	["GAINS DU JOUR"] = "DAILY EARNINGS",

	-- Menu en partie
	["REPRENDRE"] = "RESUME",
	["LA PARTIE CONTINUE"] = "THE GAME GOES ON",
	["MENU PRINCIPAL"] = "MAIN MENU",

	-- Transition vers la partie
	["DÉPLOIEMENT"] = "DEPLOYING",

	-- Lecteur de démo (écran Apprendre)
	["MAP {name} ABSENTE"] = "MAP {name} MISSING",
	["DÉCOR INDISPONIBLE"] = "SCENERY UNAVAILABLE",
	["CLIP À ENREGISTRER"] = "CLIP TO BE RECORDED",

	-- Feedback (écran) ; les messages du serveur arrivent sous forme de gabarits français (FeedbackService)
	["SIGNALE UN BUG OU PARTAGE UNE IDÉE"] = "REPORT A BUG OR SHARE AN IDEA",
	["Ton message (10 à 500 caractères)…"] = "Your message (10 to 500 characters)…",
	["Message trop court (min. {n} car.)."] = "Message too short (min. {n} chars).",
	["Envoi…"] = "Sending…",
	["Trop d'envois, réessaie dans quelques secondes."] = "Too many submissions, try again in a few seconds.",
	["Message entre {min} et {max} caractères."] = "Message must be between {min} and {max} characters.",
	["Réessaie dans {n} s."] = "Try again in {n} s.",
	["Système indisponible."] = "System unavailable.",
	["Limite de {n} feedbacks par semaine atteinte."] = "Limit of {n} feedback messages per week reached.",
	["Système indisponible, réessaie plus tard."] = "System unavailable, try again later.",
	["Merci pour ton feedback !"] = "Thanks for your feedback!",
	["Erreur lors de l'envoi."] = "Error while sending.",

	-- Écran de chargement (même traduction que la table locale de first/LoadingRules, qui ne peut pas lire Locale)
	["CHARGEMENT"] = "LOADING",
	["ENTRAÎNEMENT"] = "TRAINING",
	["RETOUR EN PARTIE"] = "BACK TO GAME",
	["REJOINDRE UN AMI"] = "JOINING A FRIEND",
}
