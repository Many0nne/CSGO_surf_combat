# CSGO

## Overview

Projet Rojo qui synchronise une expérience Roblox depuis l'arborescence `src/`.

## Current Structure

```text
CSGO/
  aftman.toml
  CLAUDE.md
  CSGO.rbxlx
  default.project.json
  feedback.md
  logs.md
  README.md
  SOURCE_ENGINE_SURF.md
  sourcemap.json
  SPEC.md
  src/
    client/
      init.client.luau
      camera/
        FPSCamera.luau
      debug/
        Noclip.luau
      input/
        InputModule.luau
      systems/
        movement/
          BhopSystem.luau
          CharacterDimensions.luau
          CoyoteJump.luau
          CrouchSystem.luau
          GroundDetection.luau
          HeadCollisionResolver.luau
          MovementController.luau
          PhysicsStepAir.luau
          PhysicsStepGround.luau
          SlopeSystem.luau
          StepupSystem.luau
          WallSlide.luau
        weapon/
          AnimationSoundSystem.luau
          MeleeHitDetection.luau
          ScopeSystem.luau
          ViewmodelSystem.luau
          WeaponSystem.luau
      ui/
        SettingsMenu.luau
        Speedometer.luau
    server/
      init.server.luau
      SettingsStore.luau
      Validator.luau
    shared/
      CameraConfig.luau
      MovementConfig.luau
      MovementState.luau
      NetworkProtocol.luau
      PhysicsUtils.luau
      WeaponConfig.luau
```

## Rojo Mapping

- `src/shared` -> `ReplicatedStorage/Shared`
- `src/server` -> `ServerScriptService/Server`
- `src/client` -> `StarterPlayerScripts/Client`

## Description des fichiers

- `default.project.json`: configuration Rojo qui mappe l'arborescence `src/` vers le projet Roblox.
- `aftman.toml`: gère la version et la configuration de Rojo (outil de synchronisation/build).
- `CLAUDE.md`: guide de contexte et conventions pour travailler dans ce dépôt.
- `SPEC.md`: spécification détaillée du projet (mappings, architecture, constantes). Utilisez-le comme source de vérité.
- `src/`: code source organisé par rôle : `client/`, `server/`, `shared/`.
  - `src/client`: scripts et systèmes côté client (caméra, input, UI, systèmes de mouvement).
  - `src/server`: scripts côté serveur (stores, validateurs, logique persistante).
  - `src/shared`: modules partagés (protocoles réseau, états, configs, utils physiques).
- `README.md`: informations générales et instructions d'usage du dépôt.
- `SOURCE_ENGINE_SURF.md`: notes de référence sur le surf Source et les comportements de mouvement à reproduire.
- `CSGO.rbxlx`: artefact de build produit par `rojo build`.
- `feedback.md`: journal de retours et notes de travail.
- `logs.md`: journalisation et traces de debug.
- `sourcemap.json`: mapping de source pour la synchro Rojo.

## Notes

- Garder `default.project.json` synchronisé avec l'arborescence `src/` (mappings Rojo).
- `aftman.toml` gère la version de Rojo utilisée.
- `SPEC.md` contient la spécification détaillée (mappings, architecture, constantes). Utilisez-le comme source de vérité pour la structure des fichiers.
- Valeurs récentes : `AIR_ACCEL=50`, `GRAVITY=-125`, `MAX_FALL_SPEED=100`, `AUTO_BHOP=true`.
- Consigne de lecture : pour les revues de code, analyses ou demandes de modification, ne lire que les fichiers strictement concernés par l'étape ou la demande.
- Évitez d'analyser ou d'indexer l'ensemble du dépôt sauf si la tâche l'exige explicitement. Quand vous consultez des fichiers, précisez lesquels dans votre message ou votre PR.

## Descriptions courtes des fichiers dans `src/`

- `src/client/init.client.luau`: point d'entrée client, initialise les modules côté client.
- `src/client/camera/FPSCamera.luau`: contrôles et logique de la caméra FPS.
- `src/client/debug/Noclip.luau`: outil de debug pour activer/désactiver le noclip.
- `src/client/input/InputModule.luau`: gestion des entrées utilisateur et mapping des actions.
- `src/client/systems/movement/BhopSystem.luau`: implémentation du bunnyhop (saut en chaîne).
- `src/client/systems/movement/CharacterDimensions.luau`: calcule les dimensions du personnage et les hitboxes debout/accroupi.
- `src/client/systems/movement/CoyoteJump.luau`: gestion du "coyote time" pour les sauts.
- `src/client/systems/movement/CrouchSystem.luau`: logique de position accroupie, hauteur caméra et hitbox.
- `src/client/systems/movement/GroundDetection.luau`: détection du sol et transitions air/sol.
- `src/client/systems/movement/HeadCollisionResolver.luau`: résolution des collisions tête (plafond, mur haut) lors du déplacement.
- `src/client/systems/movement/MovementController.luau`: orchestrateur principal du mouvement (boucle Heartbeat, transitions d'état).
- `src/client/systems/movement/PhysicsStepAir.luau`: étape physique aérienne (air accelerate Source + cap `AIR_SPEED_CAP`).
- `src/client/systems/movement/PhysicsStepGround.luau`: étape physique pour l'état au sol.
- `src/client/systems/movement/SlopeSystem.luau`: gestion des pentes et adaptation du mouvement.
- `src/client/systems/movement/StepupSystem.luau`: logique pour monter sur de petits obstacles.
- `src/client/systems/movement/WallSlide.luau`: glisse le long des murs/rampe avec conservation de normale surf si on avance vers la rampe.
- `src/client/systems/weapon/AnimationSoundSystem.luau`: gestion des marqueurs sons sur les AnimationTracks.
- `src/client/systems/weapon/MeleeHitDetection.luau`: raycast et calcul de dégâts melee (backstab inclus).
- `src/client/systems/weapon/ScopeSystem.luau`: gestion du scope (FOV, GUI, sensibilité caméra) pour les armes à lunette.
- `src/client/systems/weapon/ViewmodelSystem.luau`: gestion du viewmodel, des animations et des sons des armes en vue FPS.
- `src/client/systems/weapon/WeaponSystem.luau`: logique client des armes, munitions, recharge et vitesse liée à l'arme.
- `src/client/ui/SettingsMenu.luau`: interface des réglages côté client.
- `src/client/ui/Speedometer.luau`: affichage de la vitesse du joueur.
- `src/server/init.server.luau`: point d'entrée serveur, initialise les services côté serveur.
- `src/server/SettingsStore.luau`: stockage et récupération des paramètres serveur.
- `src/server/Validator.luau`: routines de validation côté serveur (anti-cheat, sanity checks).
- `src/shared/CameraConfig.luau`: constantes caméra (FOV, sensibilité, pitch min/max, hauteurs, lerp speed, scope sens multiplier).
- `src/shared/MovementConfig.luau`: constantes physique du mouvement uniquement (vitesses, accel, friction, saut, pentes, bhop, réseau, hitbox).
- `src/shared/MovementState.luau`: structure d'état partagée pour le mouvement du joueur.
- `src/shared/NetworkProtocol.luau`: définitions des messages et du protocole réseau.
- `src/shared/PhysicsUtils.luau`: fonctions utilitaires pour la physique.
- `src/shared/WeaponConfig.luau`: définitions partagées des armes et de leurs paramètres par défaut.

## Common Commands

```bash
rojo serve
rojo build -o "CSGO.rbxlx"
```
