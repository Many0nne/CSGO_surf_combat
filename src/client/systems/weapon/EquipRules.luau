--!strict
-- Règles pures de la sélection d'une arme (#159, #183, #404) : verrou de l'equip et identité de l'action en cours (equip,
-- tir, coup, rechargement), pour qu'un délai resté d'une action précédente ne termine jamais la nouvelle.

local EquipRules = {}

-- Verrou d'equip par défaut (s) d'une arme sans `EquipTime`.
EquipRules.DEFAULT_EQUIP_TIME = 0.8

-- Cette méthode permet de lire la durée pendant laquelle une arme reste inutilisable après sa sortie lorsqu'elle est
-- équipée : `EquipTime` de la config (valeur CS:GO, #404), indépendant de la longueur de la piste Equip, que l'action
-- suivante coupe si elle dure plus longtemps.
function EquipRules.lockTime(cfg: any): number
	local equipTime = cfg and cfg.EquipTime
	if type(equipTime) == "number" and equipTime >= 0 then
		return equipTime
	end
	return EquipRules.DEFAULT_EQUIP_TIME
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
