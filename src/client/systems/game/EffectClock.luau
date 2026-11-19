-- Horloge des effets visuels (#586) : temps qui avance comme os.clock(), sauf pendant le rejeu d'une partie filmé au
-- ralenti (debug/MatchReplay), où il avance à la vitesse du rejeu. Les effets animés à la main (rayons, PAN !, éclair,
-- CIRCUIT, douilles) lisent `now`, les durées réelles (Debris, task.delay, TweenInfo) passent par `real` / `delay` /
-- `tweenInfo`, les émetteurs de particules par `particleScale` : une fois la vidéo remise à vitesse normale, chaque
-- effet dure ce qu'il dure en partie. Hors rejeu, l'échelle vaut 1 et rien ne change.
local EffectClock = {}

local scale = 1
-- Point de raccord : instant os.clock du dernier changement d'échelle et temps des effets à cet instant
local baseReal = os.clock()
local baseTime = baseReal

-- Cette méthode permet de lire le temps des effets lorsqu'un effet naît ou avance d'une image.
function EffectClock.now(): number
	return baseTime + (os.clock() - baseReal) * scale
end

-- Cette méthode permet de changer la vitesse des effets lorsque le rejeu démarre au ralenti ou se termine (1) ; le temps
-- reste continu (les effets en cours ne sautent pas).
function EffectClock.setScale(value: number)
	local now = os.clock()
	baseTime = baseTime + (now - baseReal) * scale
	baseReal = now
	scale = if value > 0 and value == value then value else 1
end

-- Cette méthode permet de lire la vitesse des effets lorsqu'un émetteur de particules ou une piste s'y règle.
function EffectClock.scale(): number
	return scale
end

-- Cette méthode permet de convertir une durée des effets en durée réelle lorsqu'elle part dans Debris ou task.delay.
function EffectClock.real(duration: number): number
	return duration / scale
end

-- Cette méthode permet d'attendre une durée des effets avant d'appeler `fn` lorsqu'un effet enchaîne deux temps.
function EffectClock.delay(duration: number, fn: (...any) -> (), ...: any): thread
	return task.delay(duration / scale, fn, ...)
end

-- Cette méthode permet d'adapter un TweenInfo à la vitesse des effets lorsqu'une interpolation part (identique hors
-- rejeu).
function EffectClock.tweenInfo(info: TweenInfo): TweenInfo
	if scale == 1 then
		return info
	end
	return TweenInfo.new(
		info.Time / scale,
		info.EasingStyle,
		info.EasingDirection,
		info.RepeatCount,
		info.Reverses,
		info.DelayTime / scale
	)
end

return EffectClock
