return function(T, Loader)
	local Rules = Loader.new():require("src/client/ui/DemoClipRules")

	-- Cette méthode permet de fabriquer un clip de test lorsqu'un cas a besoin d'une trajectoire connue : avance de 10
	-- studs par échantillon en X, lacet de 3° par échantillon, touches données par `keysOf(i)`.
	local function lineClip(count: number, keysOf: ((number) -> number)?): any
		local samples = {}
		for i = 1, count do
			table.insert(samples, {
				x = (i - 1) * 10,
				y = 5,
				z = -2,
				eye = 2.1,
				yaw = (i - 1) * 3,
				pitch = -10,
				keys = if keysOf then keysOf(i) else 0,
				speed = 100 + i,
			})
		end
		return { version = 1, hz = 30, map = "Dizzy", samples = samples }
	end

	T.describe("DemoClipRules : format texte", function()
		T.it("relit ce qu'il écrit sans dérive sur une longue prise (écarts entre valeurs arrondies)", function()
			local long = lineClip(600)
			for i, sample in long.samples do
				sample.x = i * 0.3333
				sample.yaw = -i * 1.006
			end
			local text = Rules.encode(long)
			local back = Rules.decode(text)
			T.expectNear(back.samples[600].x, 600 * 0.3333, 0.005 + 1e-9)
			T.expectNear(back.samples[600].yaw, -600 * 1.006, 0.005 + 1e-9)
			T.expectEqual(string.match(text, "\n([^\n]*)$"), "33 0 0 0 -101 0 0 7000", "écarts en centièmes")
		end)

		T.it("relit exactement ce qu'il écrit (arrondi à 0,01 stud et 0,01°)", function()
			local clip = lineClip(5, function(i)
				return i
			end)
			clip.samples[2].x = 12.3456
			local decoded = Rules.decode(Rules.encode(clip))
			T.expect(decoded ~= nil, "décodé")
			T.expectEqual(decoded.hz, 30)
			T.expectEqual(decoded.map, "Dizzy")
			T.expectEqual(#decoded.samples, 5)
			T.expectNear(decoded.samples[2].x, 12.35, 1e-9)
			T.expectEqual(decoded.samples[3].keys, 3)
			T.expectNear(decoded.samples[5].speed, 105, 1e-9)
		end)

		T.it("refuse un texte vide, un autre en-tête, une autre version ou une ligne abîmée", function()
			T.expectEqual(Rules.decode(""), nil, "vide")
			T.expectEqual(Rules.decode("VIDEO 1 30 Dizzy\n1 2 3 4 5 6 7 8\n1 2 3 4 5 6 7 8"), nil, "en-tête")
			T.expectEqual(Rules.decode("CLIP 2 30 Dizzy\n1 2 3 4 5 6 7 8\n1 2 3 4 5 6 7 8"), nil, "version")
			local _, why = Rules.decode("CLIP 1 30 Dizzy\n1 2 3 4 5 6 7 8\n1 2 3")
			T.expectEqual(why, "ligne 3 illisible")
			local _, word = Rules.decode("CLIP 1 30 Dizzy\n1 2 3 4 5 6 7 8\n1 2 x 4 5 6 7 8")
			T.expectEqual(word, "ligne 3 illisible", "mot non numérique")
		end)

		T.it("accepte les fins de ligne CRLF des modules formatés par StyLua", function()
			local clip = Rules.decode("CLIP 1 30 Dizzy\r\n1 2 3 4 5 6 7 8\r\n1 2 3 4 5 6 7 8\r\n")
			T.expect(clip ~= nil, "décodé")
			T.expectEqual(clip.map, "Dizzy")
			T.expectEqual(#clip.samples, 2)
			T.expectNear(clip.samples[2].x, 0.02, 1e-9)
			T.expectEqual(Rules.decode("CLIP 1 30 Dizzy\n1 2 3 4 5 6 7 8"), nil, "un seul échantillon")
		end)

		T.it("range chaque action de KEY_ORDER sur son bit", function()
			local mask = Rules.keysMask({ left = true, jump = true })
			T.expectEqual(mask, 2 + 16)
			T.expectEqual(Rules.isHeld(mask, "left"), true)
			T.expectEqual(Rules.isHeld(mask, "jump"), true)
			T.expectEqual(Rules.isHeld(mask, "forward"), false)
			T.expectEqual(Rules.isHeld(mask, "right"), false)
			T.expectEqual(Rules.isHeld(mask, "inconnue"), false)
		end)
	end)

	T.describe("DemoClipRules.sampleAt", function()
		local clip = lineClip(31)

		T.it("passe exactement par les échantillons", function()
			local s = Rules.sampleAt(clip, 10 / 30)
			T.expectNear(s.x, 100, 1e-6)
			T.expectNear(s.yaw, 30, 1e-6)
			T.expectNear(s.eye, 2.1, 1e-6)
		end)

		T.it("interpole entre deux échantillons sans saccade (mi-chemin d'une ligne droite)", function()
			local s = Rules.sampleAt(clip, 10.5 / 30)
			T.expectNear(s.x, 105, 1e-6)
			T.expectNear(s.yaw, 31.5, 1e-6)
			T.expectNear(s.speed, 111.5, 1e-6)
			T.expectNear(s.pitch, -10, 1e-6)
		end)

		T.it("lit la rotation de la souris dans le lacet : 3° par échantillon à 30 Hz = 90°/s à droite", function()
			T.expectNear(Rules.sampleAt(clip, 0.5).turn, 90, 1e-6)
			T.expectNear(Rules.turnFill(90), 90 / Rules.TURN_FULL, 1e-9)
			T.expectEqual(Rules.turnFill(-10000), -1)
		end)

		T.it("garde les touches de l'échantillon en cours, sans interpolation", function()
			local keyed = lineClip(4, function(i)
				return if i >= 3 then 8 else 1
			end)
			T.expectEqual(Rules.sampleAt(keyed, 1.9 / 30).keys, 1)
			T.expectEqual(Rules.sampleAt(keyed, 2.05 / 30).keys, 8)
			T.expectEqual(Rules.sampleAt(keyed, 99).keys, 8, "au-delà de la fin : dernier échantillon")
		end)

		T.it("s'arrête au dernier échantillon à la fin du clip", function()
			local s = Rules.sampleAt(clip, Rules.duration(clip))
			T.expectNear(s.x, 300, 1e-6)
			T.expectNear(Rules.duration(clip), 1, 1e-9)
		end)
	end)

	T.describe("DemoClipRules : bouclage", function()
		T.it("ramène le temps dans la durée du clip", function()
			T.expectNear(Rules.loopTime(12.5, 10), 2.5, 1e-9)
			T.expectNear(Rules.loopTime(3, 10), 3, 1e-9)
			T.expectEqual(Rules.loopTime(5, 0), 0)
		end)

		T.it("fond au noir avant la fin et revient après le début", function()
			T.expectNear(Rules.loopFade(0, 10, 0.5), 1, 1e-9, "début : noir")
			T.expectNear(Rules.loopFade(0.25, 10, 0.5), 0.5, 1e-9)
			T.expectEqual(Rules.loopFade(5, 10, 0.5), 0, "milieu : rien")
			T.expectNear(Rules.loopFade(9.75, 10, 0.5), 0.5, 1e-9)
			T.expectNear(Rules.loopFade(10, 10, 0.5), 1, 1e-9, "fin : noir")
			T.expectEqual(Rules.loopFade(0.1, 0.8, 0.5), 0, "clip trop court : pas de fondu")
		end)
	end)

	T.describe("DemoClipRules : interpolation de l'enregistreur", function()
		T.it("place un échantillon entre deux images, touches de l'image la plus proche", function()
			local a = { x = 0, y = 0, z = 0, eye = 2, yaw = 10, pitch = 0, keys = 1, speed = 50 }
			local b = { x = 10, y = 4, z = 0, eye = 1, yaw = 20, pitch = 10, keys = 2, speed = 70 }
			local mid = Rules.lerpSample(a, b, 0.25)
			T.expectNear(mid.x, 2.5, 1e-9)
			T.expectNear(mid.yaw, 12.5, 1e-9)
			T.expectNear(mid.speed, 55, 1e-9)
			T.expectEqual(mid.keys, 1)
			T.expectEqual(Rules.lerpSample(a, b, 0.75).keys, 2)
		end)
	end)

	T.describe("DemoClipRules : pièces autour de la trajectoire", function()
		local clip = lineClip(31)

		T.it("relève un point tous les n échantillons, dernier compris, à hauteur des yeux", function()
			local points = Rules.pathPoints(clip, 10)
			T.expectEqual(#points, 5) -- 1, 11, 21, 31, puis le dernier
			T.expectNear(points[1].Y, 7.1, 1e-9)
			T.expectNear(points[#points].X, 300, 1e-9)
		end)

		T.it("garde une pièce proche d'un point de passage, rayon compris, et écarte les autres", function()
			local points = Rules.pathPoints(clip, 10)
			T.expectEqual(Rules.nearPath({ X = 150, Y = 7.1, Z = 90 }, 5, points, 100), true, "à 90 + 5 du chemin")
			T.expectEqual(Rules.nearPath({ X = 150, Y = 7.1, Z = 200 }, 5, points, 100), false, "trop loin")
			T.expectEqual(Rules.nearPath({ X = 150, Y = 7.1, Z = 200 }, 120, points, 100), true, "grande pièce")
		end)
	end)
end
