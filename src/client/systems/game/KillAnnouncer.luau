-- Annonceur de kills : voix « Headshot », « Double kill »… entendues par le seul joueur qui tue (KillStreakRules).
-- La série repart à 0 à sa mort et hors partie (GameStateController). Une nouvelle annonce coupe celle en cours.
-- La série est aussi montrée dans le HUD (crâne et nombre, RoundHUD.setStreak, #364), branché par onStreak.
-- Sources dans assets/sounds/Announcer/ (voix ElevenLabs), découpées par tools/audio/cut_announcer.py, publiées par Open Cloud.
local SoundService = game:GetService("SoundService")

local KillStreakRules = require(script.Parent.KillStreakRules)
local LocalSettings = require(script.Parent.Parent.settings.LocalSettings)
local SoundChannels = require(script.Parent.Parent.settings.SoundChannels)

local SOUND_IDS: { [KillStreakRules.Announcement]: string } = {
	Headshot = "rbxassetid://122155322489948",
	DoubleKill = "rbxassetid://132789744732026",
	TripleKill = "rbxassetid://105648145468219",
	QuadrupleKill = "rbxassetid://100428911430155",
	MonsterKill = "rbxassetid://86166501399595",
	Dominating = "rbxassetid://91442275712876",
	Divine = "rbxassetid://96128255139197",
}
-- Voix ~8 dB plus fortes que l'ancien ding de tête (joué à 0.7) : volume réduit pour rester au-dessus des tirs sans les couvrir
local VOLUME = 0.5

local KillAnnouncer = {}

local streak = 0
local sounds: { [string]: Sound } = {}
local playing: Sound? = nil
local streakListener: ((number) -> ())? = nil -- indicateur de série du HUD (#364)

-- Cette méthode permet de prévenir l'indicateur du HUD lorsque la série change (kill, mort, sortie de partie).
local function notify()
	if streakListener then
		streakListener(streak)
	end
end

-- Cette méthode permet de jouer une annonce lorsque la série l'exige ; le son est créé une fois puis rejoué,
-- et coupe l'annonce encore en cours.
local function play(announcement: KillStreakRules.Announcement)
	local sound = sounds[announcement]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "Announcer" .. announcement
		sound.SoundId = SOUND_IDS[announcement]
		sound.Volume = VOLUME
		sound.Parent = SoundService
		SoundChannels.announcer(sound)
		sounds[announcement] = sound
	end
	if playing and playing ~= sound then
		playing:Stop()
	end
	sound.TimePosition = 0
	sound:Play()
	playing = sound
end

-- Cette méthode permet de compter un kill du joueur local et de jouer son annonce lorsque le serveur annonce la mort
-- d'un adversaire tué par lui.
function KillAnnouncer.onKill(headshot: boolean)
	local announcement
	streak, announcement = KillStreakRules.onKill(streak, headshot)
	if announcement then
		play(announcement)
	end
	notify()
end

-- Cette méthode permet de brancher l'indicateur de série du HUD (#364) lorsque le client démarre ; il reçoit la série à
-- chaque changement, et tout de suite la série courante.
function KillAnnouncer.onStreak(listener: (number) -> ())
	streakListener = listener
	notify()
end

-- Cette méthode permet de savoir si une annonce vocale est en train de jouer lorsque la musique de fond (#286) doit
-- baisser le temps de la voix ; faux quand le canal annonces est à 0 (voix muette, la musique ne baisse pas, #405).
function KillAnnouncer.isSpeaking(): boolean
	if LocalSettings.get().volumeAnnouncer <= 0 then
		return false
	end
	return playing ~= nil and playing.IsPlaying
end

-- Cette méthode permet de remettre la série à 0 lorsque le joueur local meurt ou quitte la partie.
function KillAnnouncer.reset()
	if streak == 0 then
		return
	end
	streak = 0
	notify()
end

return KillAnnouncer
