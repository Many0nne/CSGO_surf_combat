return function(T, Loader)
	local loader = Loader.new()
	local Animator = loader:require("src/client/systems/weapon/ViewmodelAnimator")
	local WeaponConfig = loader:require("src/shared/WeaponConfig")

	-- Les viewmodels portent le même nom que les armes de WeaponConfig (attribut ViewmodelName des outils)
	local sets = {}
	for name in WeaponConfig.Weapons do
		sets[name] = Animator.compileSet(loader:require("src/client/systems/weapon/clips/" .. name))
	end

	-- Cette méthode permet de jouer un clip jusqu'au bout à 60 Hz lorsqu'un test vérifie sa durée et ses marqueurs ;
	-- retourne le temps écoulé à la fin de l'action et la liste des marqueurs franchis avec leur instant.
	local function playThrough(set, clipName: string, duration: number?)
		local anim = Animator.new(set.clips)
		T.expect(anim:play(clipName, duration), "clip " .. clipName .. " jouable")
		local elapsed, fired = 0, {}
		while anim:getAction() == clipName and elapsed < 20 do
			local _, names = anim:step(1 / 60)
			elapsed += 1 / 60
			for _, n in names do
				table.insert(fired, { name = n, t = elapsed })
			end
		end
		return elapsed, fired
	end

	-- Cette méthode permet de vérifier qu'une pose est au repos lorsqu'un clip doit finir sans à-coup.
	local function expectRest(cf, message)
		T.expectNear(cf.Position.Magnitude, 0, 1e-3, message .. " position")
		T.expectNear(cf.UpVector.Y, 1, 1e-3, message .. " orientation")
		T.expectNear(cf.LookVector.Z, -1, 1e-3, message .. " orientation")
	end

	T.describe("Clips du viewmodel", function()
		T.it("chaque arme a Idle, Equip, Shoot, Inspect, et Reload si elle a un chargeur", function()
			for name, cfg in WeaponConfig.Weapons do
				local clips = sets[name].clips
				for _, clipName in { "Idle", "Equip", "Shoot", "Inspect" } do
					T.expect(clips[clipName] ~= nil, name .. "." .. clipName)
				end
				T.expect(not cfg.Magazine or clips.Reload ~= nil, name .. ".Reload")
				T.expect(clips.Idle.looped, name .. ".Idle bouclée")
			end
		end)

		T.it("les actions finissent au repos (pas de retour brusque vers la pose du rig)", function()
			for name, set in sets do
				for clipName, clip in set.clips do
					for joint, keys in clip.tracks do
						local label = name .. "." .. clipName .. "." .. joint
						expectRest(Animator.sampleTrack(keys, clip.length), label .. " fin")
						if clipName == "Idle" then
							expectRest(Animator.sampleTrack(keys, 0), label .. " début de boucle")
						end
					end
				end
			end
		end)

		T.it("equip, tir et recharge durent exactement les temps de WeaponConfig", function()
			for name, cfg in WeaponConfig.Weapons do
				local durations = { Equip = cfg.EquipTime, Shoot = cfg.ShootAnimTime, Reload = cfg.ReloadTime }
				for clipName, duration in durations do
					if sets[name].clips[clipName] then
						local elapsed = playThrough(sets[name], clipName, duration)
						T.expectNear(elapsed, duration, 1 / 30, name .. "." .. clipName)
					end
				end
			end
		end)

		T.it("chaque son déclaré a un marqueur et chaque marqueur a un son déclaré, sans doublon", function()
			for name, cfg in WeaponConfig.Weapons do
				local dynamic = {}
				for _, marker in cfg.DynamicMarkers or {} do
					dynamic[marker] = true
				end
				for clipName, clip in sets[name].clips do
					local declared = {}
					for _, sound in (cfg.AnimationSounds or {})[clipName] or {} do
						declared[sound] = true
					end
					local seen = {}
					for _, m in clip.markers do
						local label = name .. "." .. clipName .. " marqueur " .. m.name
						T.expect(declared[m.name] or dynamic[m.name], label .. " sans son déclaré")
						local key = m.name .. "@" .. m.t
						T.expect(not seen[key], label .. " en double à t = " .. m.t)
						seen[key] = true
						seen[m.name] = true
					end
					for sound in declared do
						T.expect(seen[sound], name .. "." .. clipName .. " : son " .. sound .. " jamais joué")
					end
				end
			end
		end)

		T.it("les marqueurs tombent pendant l'action, une seule fois chacun", function()
			for name, cfg in WeaponConfig.Weapons do
				local durations = { Equip = cfg.EquipTime, Shoot = cfg.ShootAnimTime, Reload = cfg.ReloadTime }
				for clipName, duration in durations do
					local clip = sets[name].clips[clipName]
					if clip then
						local elapsed, fired = playThrough(sets[name], clipName, duration)
						T.expectEqual(#fired, #clip.markers, name .. "." .. clipName .. " nombre de marqueurs")
						for _, f in fired do
							T.expect(f.t <= elapsed + 1e-6, name .. "." .. clipName .. " " .. f.name .. " avant la fin")
						end
					end
				end
			end
		end)

		T.it("le coup de couteau est résolu tôt dans le clip (réactivité)", function()
			local clip = sets.Butterfly.clips.Shoot
			for _, m in clip.markers do
				if m.name == "Stab" then
					T.expect(m.t <= 0.3 * clip.length, "Stab à " .. m.t .. " s")
				end
			end
		end)
	end)
end
