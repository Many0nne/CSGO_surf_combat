local AnimationSoundSystem = {}

-- Cette méthode permet de retirer les doublons d'une liste de noms de sons en gardant l'ordre lorsque
-- WeaponConfig déclare deux fois le même son (sinon le marqueur serait connecté deux fois et le son joué en double).
function AnimationSoundSystem.uniqueNames(names: { string }?): { string }
	local seen = {}
	local out = {}
	local list: { string } = names or {}
	for _, name in list do
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(out, name)
		end
	end
	return out
end

-- Cette méthode permet de filtrer les sons configurés dont le marqueur "X Sound" est déjà géré par un override
-- lorsque playAnimation reçoit des marqueurs dynamiques (ex. "Stab Sound" du couteau).
function AnimationSoundSystem.withoutOverridden(names: { string }?, overrides: { [string]: any }?): { string }
	local out = {}
	for _, name in AnimationSoundSystem.uniqueNames(names) do
		if not (overrides and overrides[name .. " Sound"] ~= nil) then
			table.insert(out, name)
		end
	end
	return out
end

-- Cette méthode permet d'arrêter les sons nommés du dossier Sounds d'un viewmodel lorsqu'il est rangé
-- (recharge annulée par un switch d'arme).
function AnimationSoundSystem.stopSounds(model: Model, names: { string })
	local sounds = model:FindFirstChild("Sounds")
	if not sounds then
		return
	end
	for _, name in AnimationSoundSystem.uniqueNames(names) do
		local s = sounds:FindFirstChild(name)
		if s and s:IsA("Sound") and s.IsPlaying then
			s:Stop()
		end
	end
end

-- Cette méthode permet de calculer la vitesse de lecture qui cale une animation de durée `length` sur `target`
-- secondes lorsque la durée gameplay diffère de l'asset ; bornée à [minSpeed, maxSpeed], 1 si une durée est inconnue.
function AnimationSoundSystem.computePlaybackSpeed(
	length: number?,
	target: number?,
	minSpeed: number,
	maxSpeed: number
): number
	if not length or not target or length <= 0 or target <= 0 then
		return 1
	end
	return math.clamp(length / target, minSpeed, maxSpeed)
end

-- Cette méthode permet de déconnecter et vider une liste de connexions lorsqu'une piste est remplacée ou le viewmodel rangé.
function AnimationSoundSystem.disconnectAll(conns: { RBXScriptConnection })
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
end

function AnimationSoundSystem.getAnimator(model: Model): Animator?
	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	if controller then
		local animator = controller:FindFirstChildWhichIsA("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = controller
		end
		return animator
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		local animator = humanoid:FindFirstChildWhichIsA("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		return animator
	end

	return nil
end

-- Connecte les sons déclarés dans soundNames depuis WeaponConfig.AnimationSounds[animName].
-- Convention : son "X" est déclenché par le marqueur "X Sound" dans l'animation.
function AnimationSoundSystem.connectSoundMarkers(
	track: AnimationTrack,
	model: Model,
	soundNames: { string }
): { RBXScriptConnection }
	local conns = {}
	local sounds = model:FindFirstChild("Sounds")
	if not sounds then
		return conns
	end
	for _, name in AnimationSoundSystem.uniqueNames(soundNames) do
		local s = sounds:FindFirstChild(name)
		if s and s:IsA("Sound") then
			local c = track:GetMarkerReachedSignal(name .. " Sound"):Connect(function()
				s:Play()
			end)
			table.insert(conns, c)
		end
	end
	return conns
end

function AnimationSoundSystem.connectSoundMarker(
	track: AnimationTrack,
	model: Model,
	markerName: string,
	soundName: string
): RBXScriptConnection?
	local sounds = model:FindFirstChild("Sounds")
	if not sounds then
		return nil
	end
	local s = sounds:FindFirstChild(soundName)
	if s and s:IsA("Sound") then
		return track:GetMarkerReachedSignal(markerName):Connect(function()
			s:Play()
		end)
	end
	return nil
end

-- Comme connectSoundMarker mais le nom du son est résolu dynamiquement au moment où le marker fire.
function AnimationSoundSystem.connectDynamicMarker(
	track: AnimationTrack,
	model: Model,
	markerName: string,
	getSound: () -> string
): RBXScriptConnection?
	local sounds = model:FindFirstChild("Sounds")
	if not sounds then
		return nil
	end
	return track:GetMarkerReachedSignal(markerName):Connect(function()
		local soundName = getSound()
		local s = sounds:FindFirstChild(soundName)
		if s and s:IsA("Sound") then
			s:Play()
		end
	end)
end

return AnimationSoundSystem
