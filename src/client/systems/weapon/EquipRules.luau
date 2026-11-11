--!strict
-- Règles pures de la sélection d'une arme (#159, #183) : durée de l'equip et identité de l'action en cours (equip, tir,
-- coup, rechargement), pour qu'un délai resté d'une action précédente ne termine jamais la nouvelle.

local EquipRules = {}

-- Durée maximale d'attente du chargement de la piste Equip (#184) : au-delà, l'equip retombe sur `EquipTime`.
EquipRules.LOAD_TIMEOUT = 2

-- Cette méthode permet de lire la vitesse de lecture de la piste Equip lorsque la config en déclare une (> 0) ;
-- sinon 1. Seul point de lecture de `EquipAnimSpeed` : le viewmodel (lecture) et WeaponSystem (durée) l'utilisent tous deux.
function EquipRules.animSpeed(configSpeed: number?): number
	if configSpeed and configSpeed > 0 then
		return configSpeed
	end
	return 1
end

-- Cette méthode permet de calculer la durée d'un equip lorsque la piste est connue (longueur > 0, vitesse > 0) ;
-- sinon elle renvoie la durée de repli de la config.
function EquipRules.duration(animLength: number, animSpeed: number, fallback: number): number
	if animLength > 0 and animSpeed > 0 then
		return animLength / animSpeed
	end
	return fallback
end

-- Cette méthode permet de savoir combien de temps l'arme reste inutilisable après l'attente `waited` : la durée de
-- l'animation dès que la piste est chargée (`animLength` > 0, comptée depuis ce chargement, par prudence), nil tant
-- qu'elle existe mais n'est pas chargée (0), et `EquipTime` (`fallback`) sans piste (nil) ou une fois `timeout` écoulé,
-- diminué de l'attente déjà passée (jamais d'attente cumulée plus longue que `EquipTime` pour une arme sans piste).
function EquipRules.settleTime(
	animLength: number?,
	configSpeed: number?,
	fallback: number,
	waited: number,
	timeout: number
): number?
	if animLength == nil then
		return math.max(0, fallback - waited)
	end
	if animLength > 0 then
		return EquipRules.duration(animLength, EquipRules.animSpeed(configSpeed), fallback)
	end
	if waited >= timeout then
		return math.max(0, fallback - waited)
	end
	return nil
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
