-- Lancement du client (#480) : remplace l'écran de chargement de Roblox (ou le gui d'une téléportation) par celui du jeu
-- dès la première image. Le client (StarterPlayerScripts) dit quand le lever : LoadingScreen.setReadiness.
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local LoadingScreen = require(script.Parent:WaitForChild("LoadingScreen"))

ReplicatedFirst:RemoveDefaultLoadingScreen()
LoadingScreen.arrive()
