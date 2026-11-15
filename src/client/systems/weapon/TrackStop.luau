--!strict
-- Arrêt des pistes du viewmodel (#368). Une piste non bouclée arrivée à sa fin s'efface d'elle-même en ~0,3 s
-- (IsPlaying faux, poids encore > 0) ; pendant ce fondu, Roblox ignore Stop(0) et AdjustWeight(0, 0). Un coup de
-- couteau lancé à ce moment (AttackFadeTime = 0) se mélangeait au reste de l'Equip, de même priorité, et ne sortait
-- qu'à moitié avant de se déplier : mesuré en Studio, 154 px au premier saut de la main au lieu de 302 px.

local TrackStop = {}

-- Cette méthode permet d'arrêter une piste avec le fondu demandé ; sans fondu, elle coupe aussi le fondu de fin
-- naturel en relançant la piste sur sa dernière image puis en l'arrêtant aussitôt (rien n'est rendu entre les deux).
function TrackStop.stop(track: AnimationTrack?, fadeTime: number?)
	if not track then
		return
	end
	if fadeTime == 0 and not track.IsPlaying and track.WeightCurrent > 0 then
		track:Play(0)
		track.TimePosition = track.Length
	end
	track:Stop(fadeTime)
end

return TrackStop
