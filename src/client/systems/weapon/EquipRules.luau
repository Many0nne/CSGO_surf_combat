--!strict
-- Règles pures de la sélection d'une arme (#159, #183) : durée de l'equip et identité de l'action en cours (equip, tir,
-- coup, rechargement), pour qu'un délai resté d'une action précédente ne termine jamais la nouvelle.

local EquipRules = {}

-- Cette méthode permet de calculer la durée d'un equip lorsque la piste est connue (longueur > 0, vitesse > 0) ;
-- sinon elle renvoie la durée de repli de la config.
function EquipRules.duration(animLength: number, animSpeed: number, fallback: number): number
	if animLength > 0 and animSpeed > 0 then
		return animLength / animSpeed
	end
	return fallback
end

-- Cette méthode permet de créer le compteur d'actions : chaque action reçoit un jeton, et seul le dernier jeton émis
-- (tant qu'il n'est pas invalidé) reste courant.
function EquipRules.newGate()
	local gate = { current = 0 }

	-- Cette méthode permet de démarrer une action (equip, tir, coup, rechargement) ; elle périme tous les jetons précédents.
	function gate.begin(): number
		gate.current += 1
		return gate.current
	end

	-- Cette méthode permet d'annuler l'action en cours lorsque l'arme est rangée ou le personnage réapparaît.
	function gate.invalidate()
		gate.current += 1
	end

	-- Cette méthode permet de savoir si un délai appartient encore à l'action en cours avant de la terminer.
	function gate.isCurrent(token: number): boolean
		return token == gate.current
	end

	return gate
end

return EquipRules
