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
function AnimationSoundSystem.connectSoundMarkers(track: AnimationTrack, model: Model, soundNames: {string})
	local sounds = model:FindFirstChild("Sounds")
	if not sounds then return end
	for _, name in soundNames do
		local s = sounds:FindFirstChild(name)
		if s and s:IsA("Sound") then
			track:GetMarkerReachedSignal(name .. " Sound"):Connect(function()
				s:Play()
			end)
		end
	end
end

return AnimationSoundSystem
