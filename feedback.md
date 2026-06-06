Les deux symptômes ne sont en fait qu'un seul bug, et c'est une conséquence directe d'avoir réparé le tunneling : avant, à grande vitesse, tu traversais la rampe, donc tu n'entrais jamais réellement en contact avec elle. Maintenant que la collision tient, le personnage touche vraiment la rampe — et ça expose une mauvaise classification du sol qui était là depuis le début mais masquée.
La cause commune : la rampe surf est classée « sol »
Regarde la transition d'état dans MovementController :
luaif isOnGround then
    if state == MovementState.AIRBORNE or state == MovementState.CROUCHING then
        velocity = Vector3.new(velocity.X, 0, velocity.Z)  -- ← Y écrasé à 0
        surfNormal = nil                                    -- ← surf désactivée
    end
    state = ... GROUNDED ...
Si GroundDetection renvoie onGround = true sur la rampe surf, alors d'un coup :

velocity.Y passe à 0 → tu ne peux plus glisser ni vers le haut ni vers le bas (« bloque instantanément »).
l'état devient GROUNDED → tu peux sauter, la rampe compte comme un sol.
surfNormal = nil → la physique surf s'arrête.

Donc les deux symptômes sortent du même faux grounding. Reste à comprendre pourquoi la rampe se fait classer marchable.
Pourquoi ça grounde sur une rampe steep
Dans GroundDetection, tu écrases la normale du spherecast par un raycast central « pour avoir la vraie normale de face » :
lualocal normal = result.Normal
local centerRay = workspace:Raycast(origin, CAST_DIR, params)  -- CAST_DIR = -(HALF_HEIGHT + 0.5)
if centerRay then
    normal = centerRay.Normal
end
Deux problèmes se combinent :

CAST_DIR est trop long (HALF_HEIGHT + CAST_SKIN = 2.4 + 0.5 = 2.9). Sur une rampe courbe, le rayon central file plus bas que le point de contact réel et tape soit une portion plus plate de la courbe, soit carrément le sol sous la rampe → normale Y >= 0.7 → marchable.
Aucun séparateur dur surf/marchable. La classification repose sur slopeAngle <= 45 (+3 hystérésis), ce qui à la frontière laisse passer des normales surf.

Patch 1 — GroundDetection : borner le rayon + garde surf dure
lua	-- Normale de FACE via raycast central, mais BORNÉ à la profondeur du contact
	-- spherecast — sinon, sur rampe courbe, le rayon file plus bas et lit une face
	-- plus plate (ou le sol SOUS la rampe) → faux "marchable".
	local normal = result.Normal
	local probeLen = result.Distance + CAST_RADIUS + 0.1
	local centerRay = workspace:Raycast(origin, Vector3.new(0, -probeLen, 0), params)
	if centerRay then
		normal = centerRay.Normal
	end

	-- Garde "montée rapide"
	if velocityY and velocityY > Config.JUMP_VELOCITY * 0.5 then
		return GROUND_MISS
	end

	-- SURF : une surface non-marchable ne grounde JAMAIS. C'est le séparateur dur
	-- entre "sol" et "rampe surf" → on reste airborne et WallSlide gère le glissement.
	if normal.Y < Config.SURF_NORMAL_Y then
		return GROUND_MISS
	end

	local cosAngle   = math.clamp(normal:Dot(Vector3.yAxis), -1, 1)
	local slopeAngle = math.deg(math.acos(cosAngle))
	local maxAngle   = Config.SLOPE_ANGLE_MAX + (wasGrounded and 3 or 0)
	local onGround   = slopeAngle <= maxAngle
La garde normal.Y < SURF_NORMAL_Y → GROUND_MISS est ce qui répare les deux symptômes en une fois : sur la rampe surf tu restes airborne, velocity.Y est conservée, surfNormal reste actif, et tu ne peux plus sauter.
Note : SURF_NORMAL_Y = 0.7 (≈ 45.6°) est désormais le seuil qui tranche, donc l'hystérésis +3 ne joue plus que dans la bande 42–45.6° (sol marchable franc), ce qui est le comportement voulu.
Patch 2 — commitMove : ne pas clamper un contact rasant
Même une fois le grounding corrigé, il reste un piège : pendant un slide surf correct, ta capsule longe la rampe à SKIN près. commitMove relance alors un hullCast depuis lastSafePos, qui est collé à la rampe → le blockcast part au contact, renvoie une distance ≈ 0, et moved = max(0, 0 - SKIN) = 0 → position figée → slide tué.
Il faut distinguer un contact rasant (on glisse parallèlement à la surface) d'une obstruction frontale (mur). On n'ampute le mouvement que si le delta entre vraiment dans le plan :
luafunction WallSlide.commitMove(fromSafe, candidate, velocity, crouchInfo)
	local r = crouchInfo.radius - 0.05
	local rtb, rtt = crouchInfo.rootToBottom, crouchInfo.rootToTop
	local delta = candidate - fromSafe
	if delta.Magnitude < 1e-5 then return candidate, velocity end
	local dir = delta.Unit

	local hit = hullCast(fromSafe, r, rtb, rtt, delta)
	if not hit then
		if penInfoRaw(candidate, r - 0.05, rtb, rtt) then
			return fromSafe, clipVelocity(velocity, dir, 1.0)
		end
		return candidate, velocity
	end

	-- Contact rasant : on longe la surface (dir quasi ⟂ normale). Le hull touche déjà
	-- la rampe → distance ≈ 0, mais ce n'est PAS un obstacle frontal. On garde le
	-- candidat tant qu'il ne pénètre pas.
	if dir:Dot(hit.Normal) > -0.1 then
		if penInfoRaw(candidate, r - 0.05, rtb, rtt) then
			return fromSafe, clipVelocity(velocity, hit.Normal, 1.0)
		end
		return candidate, velocity
	end

	-- Obstruction frontale réelle : clamp + clip.
	local moved = math.max(0, hit.Distance - SKIN)
	local pos = fromSafe + dir * moved
	local vel = velocity
	if velocity:Dot(hit.Normal) < 0 then
		vel = clipVelocity(velocity, hit.Normal, 1.0)
	end
	return pos, vel
end
dir:Dot(hit.Normal) > -0.1 : tant que le mouvement n'entre pas franchement dans le plan (slide parallèle ⇒ produit scalaire ≈ 0), on n'ampute pas — la protection anti-tunnel reste assurée par le penInfoRaw sur le candidat et par la branche frontale.
Ordre de test
Applique d'abord le Patch 1 seul et vérifie que tu restes airborne sur la rampe (plus de saut possible, Y conservée). Si le slide « accroche » encore par à-coups, ajoute le Patch 2.
Un point à surveiller côté design : si certaines de tes rampes sont réellement ≤ 45°, elles resteront marchables par définition (SLOPE_ANGLE_MAX = 45). Pour qu'une rampe se comporte en surf, il faut qu'elle soit plus raide que ce seuil — sinon c'est la géométrie qu'il faut ajuster, pas le code.
Tu veux que je te renvoie GroundDetection.getGroundInfo en entier avec le Patch 1 intégré, pour éviter une erreur de recollage ?Opus 4.8 Moyen