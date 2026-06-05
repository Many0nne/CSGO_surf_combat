local AnimationSoundSystem = {}

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
function AnimationSoundSystem.connectSoundMarkers(track: AnimationTrack, model: Model, soundNames: {string}): {RBXScriptConnection}
	local conns = {}
	local sounds = model:FindFirstChild("Sounds")
	if not sounds then return conns end
	for _, name in soundNames do
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

function AnimationSoundSystem.connectSoundMarker(track: AnimationTrack, model: Model, markerName: string, soundName: string): RBXScriptConnection?
	local sounds = model:FindFirstChild("Sounds")
	if not sounds then return nil end
	local s = sounds:FindFirstChild(soundName)
	if s and s:IsA("Sound") then
		return track:GetMarkerReachedSignal(markerName):Connect(function()
			s:Play()
		end)
	end
	return nil
end

-- Comme connectSoundMarker mais le nom du son est résolu dynamiquement au moment où le marker fire.
function AnimationSoundSystem.connectDynamicMarker(track: AnimationTrack, model: Model, markerName: string, getSound: () -> string): RBXScriptConnection?
	local sounds = model:FindFirstChild("Sounds")
	if not sounds then return nil end
	return track:GetMarkerReachedSignal(markerName):Connect(function()
		local soundName = getSound()
		local s = sounds:FindFirstChild(soundName)
		if s and s:IsA("Sound") then s:Play() end
	end)
end

return AnimationSoundSystem
