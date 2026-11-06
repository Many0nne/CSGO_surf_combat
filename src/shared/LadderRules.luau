-- Règles pures des échelles (portage de CGameMovement::LadderMove de Source). Une échelle est un volume invisible de
-- Maps.Map.Ladders, dont le LookVector est la normale sortante (du mur vers le joueur). Le client la détecte
-- (LadderSystem) et MovementController remplace la physique sol/air par ces vitesses tant qu'il est dedans.

local LadderRules = {}

-- Dossier des volumes d'échelle dans Maps.Map
LadderRules.LADDERS_FOLDER = "Ladders"

-- part de la poussée « vers le mur » gardée quand on avance dans l'échelle : le mur l'annule (WallSlide), mais en haut
-- elle fait passer le joueur par-dessus le rebord
local OVER_TOP = 0.5

-- Cette méthode permet de calculer la vitesse sur une échelle lorsque le joueur est dans son volume : la composante de
-- l'envie de mouvement (3D, tangage compris) dirigée vers le mur devient une montée, le reste glisse le long de
-- l'échelle. Regarder vers le bas en avançant fait descendre ; reculer au sol décolle de l'échelle.
function LadderRules.climbVelocity(wishDir3D: Vector3, normal: Vector3, speed: number, onGround: boolean): Vector3
	if wishDir3D.Magnitude < 1e-4 then
		return Vector3.zero
	end
	local n = Vector3.new(normal.X, 0, normal.Z).Unit
	local wishVel = wishDir3D * speed
	local into = wishVel:Dot(n) -- < 0 : on pousse vers le mur
	local lateral = wishVel - n * into
	local velocity = lateral + Vector3.yAxis * -into
	-- vitesse le long de l'échelle bornée (en diagonale, Source la laisse monter à √2 × speed)
	if velocity.Magnitude > speed then
		velocity = velocity.Unit * speed
	end
	if into < 0 then
		velocity -= n * (-into * OVER_TOP)
	elseif onGround then
		-- au pied de l'échelle, reculer fait partir du mur au lieu de descendre dans le sol
		velocity += n * into
	end
	return velocity
end

-- Cette méthode permet de calculer la vitesse d'un saut depuis l'échelle lorsque le joueur saute dans son volume :
-- poussée le long de la normale sortante, sans élan vertical (comme Source).
function LadderRules.jumpOffVelocity(normal: Vector3, push: number): Vector3
	local n = Vector3.new(normal.X, 0, normal.Z).Unit
	return n * push
end

return LadderRules
