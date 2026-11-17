-- Règles pures du clip de la partie (#499) : tampons, séries, recalage de la caméra, durée de la phase de résultat.
return function(T, Loader)
	local loader = Loader.new()
	local R = loader:require("src/shared/HighlightClipRules")
	local GameConfig = loader:require("src/shared/GameConfig")
	local HighlightRules = loader:require("src/server/HighlightRules")

	-- Cette méthode permet de remplir une piste serveur d'un personnage qui avance sur X à `speed` studs/s, un relevé
	-- tous les 0,05 s de t0 à t1, lorsqu'un test a besoin d'un historique.
	local function movingTrack(t0: number, t1: number, speed: number)
		local track = R.newTrack()
		local t = t0
		while t <= t1 + 1e-9 do
			R.recordTrack(track, t, Vector3.new(speed * (t - t0), 0, 0), 0)
			t += 0.05
		end
		return track
	end

	-- Cette méthode permet de remplir le tampon caméra d'un tireur qui suit la même trajectoire et regarde devant lui
	-- (lacet 0 = -Z, tangage `pitch`) lorsqu'un test simule le client.
	local function cameraOf(t0: number, t1: number, speed: number, pitch: number, offset: number?)
		local ring = R.newCameraRing()
		local t = t0
		while t <= t1 + 1e-9 do
			R.pushCamera(ring, t, speed * (t - t0) + (offset or 0), 0, 0, 2.1, 0, pitch, 0, speed)
			t += 1 / R.CAMERA_HZ
		end
		return ring
	end

	T.describe("HighlightClipRules constantes", function()
		T.it("même durée maximale que la notation", function()
			T.expectEqual(R.MAX_DURATION, HighlightRules.MAX_DURATION)
		end)

		T.it("les tampons couvrent le clip le plus long et la marge de la demande", function()
			T.expect(R.CAMERA_SECONDS >= R.MAX_DURATION + HighlightRules.POST_ROLL)
			T.expect(R.TRACK_SECONDS >= R.MAX_DURATION + HighlightRules.POST_ROLL)
		end)

		T.it("phase de résultat rallongée de la durée du clip et de sa marge", function()
			T.expectEqual(R.resultDuration(nil), GameConfig.RESULT_DURATION)
			T.expectEqual(R.resultDuration(0), GameConfig.RESULT_DURATION)
			T.expectEqual(R.resultDuration(4), GameConfig.RESULT_DURATION + 4 + R.CLIP_MARGIN)
		end)
	end)

	T.describe("HighlightClipRules séries", function()
		T.it("aller-retour avec lignes absentes", function()
			local rows = { { 1.234, -5.5, 3 }, false, { 1.3, -5.25, 3.14159 } }
			local text = R.encodeSeries(rows, { 100, 100, 1000 })
			local decoded = R.decodeSeries(text, { 100, 100, 1000 }, 10)
			T.expect(decoded ~= nil)
			T.expectEqual(#decoded, 3)
			T.expectEqual(decoded[2], false)
			T.expectNear(decoded[1][1], 1.23, 1e-9)
			T.expectNear(decoded[3][2], -5.25, 1e-9)
			T.expectNear(decoded[3][3], 3.142, 1e-9)
		end)

		T.it("série vide", function()
			local decoded = R.decodeSeries(R.encodeSeries({}, { 1 }), { 1 }, 10)
			T.expectEqual(#decoded, 0)
		end)

		T.it("refuse trop de lignes, une ligne incomplète ou illisible, un autre type", function()
			T.expectEqual(R.decodeSeries("1;2;3", { 1 }, 2), nil)
			T.expectEqual(R.decodeSeries("1,2;3", { 1, 1 }, 5), nil)
			T.expectEqual(R.decodeSeries("1,x", { 1, 1 }, 5), nil)
			T.expectEqual(R.decodeSeries("1.5,2", { 1, 1 }, 5), nil)
			T.expectEqual(R.decodeSeries("1,2,3", { 1, 1 }, 5), nil)
			T.expectEqual(R.decodeSeries(42, { 1 }, 5), nil)
		end)

		T.it("une caméra de 10 s tient sous la taille maximale renvoyée", function()
			local ring = R.newCameraRing()
			for i = 1, R.CAMERA_CAPACITY do
				local t = i / R.CAMERA_HZ
				R.pushCamera(
					ring,
					t,
					1000 + 80 * t,
					50 + math.sin(t) * 20,
					-900 + 60 * t,
					2.1,
					3000 + 400 * t,
					-30,
					31,
					99
				)
			end
			local text = R.encodeSeries(R.cameraRows(ring, 0, 20), R.CAMERA_SCALES)
			T.expect(#text < R.POV_MAX_BYTES, "taille " .. #text)
		end)
	end)

	T.describe("HighlightClipRules tampon caméra", function()
		T.it("garde les CAMERA_CAPACITY derniers échantillons, dans l'ordre", function()
			local ring = R.newCameraRing(4)
			for i = 1, 6 do
				R.pushCamera(ring, i, i, 0, 0, 0, 0, 0, 0, 0)
			end
			local rows = R.cameraRows(ring, 0, 100)
			T.expectEqual(#rows, 4)
			T.expectEqual(rows[1][2], 3)
			T.expectEqual(rows[4][2], 6)
		end)

		T.it("fenêtre encadrée d'un échantillon de part et d'autre, temps relatifs", function()
			local ring = R.newCameraRing(10)
			for i = 1, 10 do
				R.pushCamera(ring, i, i, 0, 0, 0, 0, 0, 0, 0)
			end
			local rows = R.cameraRows(ring, 3.5, 5.5)
			T.expectEqual(#rows, 4, "3, 4, 5, 6")
			T.expectNear(rows[1][1], -0.5)
			T.expectNear(rows[4][1], 2.5)
		end)

		T.it("échantillon dû à la cadence, et après un recul d'horloge qui vide le tampon", function()
			local ring = R.newCameraRing()
			T.expect(R.cameraDue(ring, 10))
			R.pushCamera(ring, 10, 0, 0, 0, 0, 0, 0, 0, 0)
			T.expect(not R.cameraDue(ring, 10 + R.CAMERA_SPACING / 2))
			T.expect(R.cameraDue(ring, 10 + R.CAMERA_SPACING * 1.01))
			T.expect(R.cameraDue(ring, 5))
			R.pushCamera(ring, 5, 0, 0, 0, 0, 0, 0, 0, 0)
			T.expectEqual(ring.count, 1)
		end)
	end)

	T.describe("HighlightClipRules piste serveur", function()
		T.it("interpole entre deux relevés", function()
			local track = movingTrack(0, 1, 100)
			local pos = R.trackAt(track, 0.525)
			T.expectNear(pos.X, 52.5, 1e-6)
		end)

		T.it("absent dans un trou (mort) et loin des bords", function()
			local track = R.newTrack()
			R.recordTrack(track, 0, Vector3.zero, 0)
			R.recordTrack(track, 0.05, Vector3.zero, 0)
			R.recordTrack(track, 3, Vector3.new(50, 0, 0), 0)
			T.expectEqual(R.trackAt(track, 1.5), nil, "trou de réapparition")
			T.expectEqual(R.trackAt(track, 4), nil, "après la piste")
			T.expectEqual(R.trackAt(track, -1), nil, "avant la piste")
			T.expect(R.trackAt(track, 3.1) ~= nil, "juste après le dernier relevé")
		end)

		T.it("ignore les relevés trop rapprochés et les valeurs non finies", function()
			local track = R.newTrack()
			T.expect(R.recordTrack(track, 1, Vector3.zero, 0))
			T.expect(not R.recordTrack(track, 1.01, Vector3.zero, 0))
			T.expect(not R.recordTrack(track, 2, Vector3.new(0 / 0, 0, 0), 0))
			T.expect(not R.recordTrack(track, 2, Vector3.zero, math.huge))
		end)

		T.it("couvre TRACK_SECONDS à la cadence des joueurs, le plus ancien écrasé", function()
			local track = movingTrack(0, 30, 10)
			T.expectEqual(R.trackAt(track, 5), nil, "trop ancien")
			T.expect(R.trackAt(track, 30 - R.TRACK_SECONDS + 0.5) ~= nil)
		end)

		T.it("lignes à pas fixe, absentes hors piste", function()
			local track = movingTrack(1, 2, 10)
			local rows, any = R.trackRows(track, 0, R.rowCount(0, 2, 20), 20)
			T.expect(any)
			T.expectEqual(#rows, 41)
			T.expectEqual(rows[1], false)
			T.expectNear(rows[41][1], 10, 1e-6)
		end)
	end)

	T.describe("HighlightClipRules tirs", function()
		T.it("liste les tirs de la fenêtre dans l'ordre, les plus anciens écrasés", function()
			local ring = R.newShotRing()
			for i = 1, R.SHOT_CAPACITY + 5 do
				R.pushShot(ring, i, Vector3.new(0, 0, -1))
			end
			local shots = R.shotsIn(ring, 0, 1000)
			T.expectEqual(#shots, R.SHOT_CAPACITY)
			T.expectEqual(shots[1].t, 6)
			T.expectEqual(#R.shotsIn(ring, 10, 12), 3)
		end)
	end)

	T.describe("HighlightClipRules angles", function()
		T.it("lookOf et anglesOf sont réciproques (convention FPSCamera)", function()
			local look = R.lookOf(0, 0)
			T.expectNear(look.Z, -1, 1e-9)
			local yaw, pitch = R.anglesOf(R.lookOf(37, -12))
			T.expectNear(yaw, 37, 1e-6)
			T.expectNear(pitch, -12, 1e-6)
		end)

		T.it("cap de la racine converti en lacet de caméra", function()
			-- FPSCamera tourne la racine de CFrame.Angles(0, rad(-lacet), 0) : cap = -rad(lacet)
			T.expectNear(R.cameraYawOf(math.rad(-90)), 90, 1e-9)
		end)
	end)

	T.describe("HighlightClipRules.checkPov (recalage)", function()
		local track = movingTrack(0, 4, 50)
		-- Cette méthode permet de lire la piste serveur du test lorsque le recalage la consulte.
		local function serverAt(t)
			return (R.trackAt(track, t))
		end
		local forward = { t = 2, dir = Vector3.new(0, 0, -1), aimed = true }

		T.it("accepte une caméra honnête, en avance de la latence", function()
			local ring = cameraOf(0, 4, 50, 0, 50 * 0.15)
			local ok, why = R.checkPov(R.cameraRows(ring, 0.5, 3.5), 0.5, serverAt, { forward })
			T.expect(ok, why)
		end)

		T.it("refuse une caméra loin de la piste serveur", function()
			local ring = cameraOf(0, 4, 50, 0, 40)
			local ok, why = R.checkPov(R.cameraRows(ring, 0.5, 3.5), 0.5, serverAt, {})
			T.expect(not ok)
			T.expect(string.find(why, "position") ~= nil, why)
		end)

		T.it("refuse une caméra qui ne regarde pas le tir accepté (aimbot masqué)", function()
			local ring = cameraOf(0, 4, 50, 0)
			local up = { t = 2, dir = Vector3.new(0, 0.5, -1).Unit, aimed = true }
			local ok, why = R.checkPov(R.cameraRows(ring, 0.5, 3.5), 0.5, serverAt, { up })
			T.expect(not ok)
			T.expect(string.find(why, "visée") ~= nil, why)
		end)

		T.it("ignore la direction d'un coup de couteau (non visé)", function()
			local ring = cameraOf(0, 4, 50, 0)
			local swing = { t = 2, dir = Vector3.new(1, 0, 0), aimed = false }
			local ok, why = R.checkPov(R.cameraRows(ring, 0.5, 3.5), 0.5, serverAt, { swing })
			T.expect(ok, why)
		end)

		T.it("refuse un tir hors de la caméra, des temps non croissants, une caméra vide", function()
			local ring = cameraOf(0, 1, 50, 0)
			T.expect(not R.checkPov(R.cameraRows(ring, 0.5, 1), 0.5, serverAt, { forward }))
			T.expect(not R.checkPov({ { 0, 0, 0, 0, 2, 0, 0, 0, 0 }, { 0, 0, 0, 0, 2, 0, 0, 0, 0 } }, 0, serverAt, {}))
			T.expect(not R.checkPov({}, 0, serverAt, {}))
		end)
	end)

	T.describe("HighlightClipRules.buildPov", function()
		local track = movingTrack(0, 4, 50)
		-- Cette méthode permet de lire position et cap de la piste du test lorsque le POV est reconstruit.
		local function serverAt(t)
			return R.trackAt(track, t)
		end

		T.it("reprend les échantillons du client quand ils couvrent l'instant", function()
			local ring = cameraOf(0, 4, 50, -20)
			local rows = R.buildPov(1, 31, R.cameraRows(ring, 1, 2), serverAt, {})
			T.expectEqual(#rows, 31)
			T.expectNear(rows[1][1], 50, 1e-6)
			T.expectNear(rows[16][6], -20, 1e-6, "tangage du client")
		end)

		T.it("sans client : position serveur, tangage dégradé tiré vers le tir", function()
			local shot = { t = 2, dir = Vector3.new(0, -0.5, -1).Unit, aimed = true }
			local rows = R.buildPov(1, 61, nil, serverAt, { shot })
			local atShot = rows[31]
			T.expectNear(atShot[1], 100, 1e-6)
			T.expectNear(atShot[4], R.DEFAULT_EYE)
			local _, shotPitch = R.anglesOf(shot.dir)
			T.expectNear(atShot[6], shotPitch, 1e-6, "visée du tir à son instant")
			T.expectEqual(rows[1][6], 0, "tangage neutre loin des tirs")
		end)

		T.it("déroule le lacet (pas de saut de 360°) et marque les absences", function()
			local spin = R.newTrack()
			R.recordTrack(spin, 0, Vector3.zero, math.rad(179))
			R.recordTrack(spin, 0.05, Vector3.zero, math.rad(-179))
			local rows = R.buildPov(0, 12, nil, function(t)
				return R.trackAt(spin, t)
			end, {})
			T.expect(math.abs(rows[2][5] - rows[1][5]) < 5, "lacets voisins")
			T.expectEqual(rows[12], false, "après la piste")
		end)
	end)

	T.describe("HighlightClipRules.sampleRows", function()
		T.it("interpole et suit le plus court chemin pour un cap", function()
			local rows = { { 0, math.rad(170) }, { 10, math.rad(-170) } }
			local out = {}
			T.expect(R.sampleRows(rows, 1, 0.5, out, 2))
			T.expectNear(out[1], 5, 1e-9)
			T.expectNear(math.abs(out[2]), math.pi, 1e-6)
		end)

		T.it("absent au bord d'une ligne absente", function()
			local rows = { { 0 }, false, { 2 } }
			local out = {}
			T.expect(R.sampleRows(rows, 1, 0.2, out))
			T.expect(not R.sampleRows(rows, 1, 0.8, out))
			T.expect(not R.sampleRows(rows, 1, 1.2, out))
		end)
	end)

	T.describe("HighlightClipRules.readClip", function()
		T.it("refuse un clip abîmé ou d'une autre version", function()
			T.expectEqual(R.readClip(nil), nil)
			T.expectEqual(R.readClip({ version = 99 }), nil)
			local clip = {
				version = R.VERSION,
				duration = 4,
				killerId = 1,
				killerName = "a",
				weapon = "AWP",
				degraded = false,
				pov = "",
				actors = {},
				shots = {},
				kills = {},
			}
			T.expect(R.readClip(clip) ~= nil)
			clip.duration = 60
			T.expectEqual(R.readClip(clip), nil)
		end)
	end)
end
