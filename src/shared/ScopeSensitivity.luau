-- Sensibilité de visée selon le zoom (#115) : à la lunette, la vitesse suit le champ de vision pour qu'un même
-- geste de souris déplace la vue d'autant à l'écran qu'au hip-fire, puis le multiplicateur du joueur l'ajuste.
local ScopeSensitivity = {}

-- Cette méthode permet de donner le rapport de vitesse d'un zoom lorsque le champ de vision passe de `referenceFov`
-- à `fov` (degrés) : tan(fov/2) / tan(referenceFov/2), 1 sans zoom.
function ScopeSensitivity.zoomRatio(fov: number, referenceFov: number): number
	return math.tan(math.rad(fov) / 2) / math.tan(math.rad(referenceFov) / 2)
end

-- Cette méthode permet de donner la sensibilité effective (degrés par pixel) lorsque la caméra est au FOV `scopeFov`
-- (nil hors lunette) : sensi de base × ratio du zoom × multiplicateur du joueur.
function ScopeSensitivity.effective(baseSens: number, scopeFov: number?, referenceFov: number, userMult: number): number
	if not scopeFov then
		return baseSens
	end
	return baseSens * ScopeSensitivity.zoomRatio(scopeFov, referenceFov) * userMult
end

return ScopeSensitivity
