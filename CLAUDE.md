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
        BhopSystem.luau
        CoyoteJump.luau
        CrouchSystem.luau
        GroundDetection.luau
        MovementController.luau
        PhysicsStepAir.luau
        PhysicsStepGround.luau
        SlopeSystem.luau
        StepupSystem.luau
        WallSlide.luau
      ui/
        SettingsMenu.luau
        Speedometer.luau
    server/
      init.server.luau
      SettingsStore.luau
      Validator.luau
    shared/
      MovementConfig.luau
      MovementState.luau
      NetworkProtocol.luau
      PhysicsUtils.luau
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
- `CSGO.rbxlx`: artefact de build produit par `rojo build`.
- `feedback.md`: journal de retours et notes de travail.
- `logs.md`: journalisation et traces de debug.
- `sourcemap.json`: mapping de source pour la synchro Rojo.

## Notes

- Garder `default.project.json` synchronisé avec l'arborescence `src/` (mappings Rojo).
- `aftman.toml` gère la version de Rojo utilisée.
- `SPEC.md` contient la spécification détaillée (mappings, architecture, constantes). Utilisez-le comme source de vérité pour la structure des fichiers.
- Consigne de lecture : pour les revues de code, analyses ou demandes de modification, ne lire que les fichiers strictement concernés par l'étape ou la demande.
- Évitez d'analyser ou d'indexer l'ensemble du dépôt sauf si la tâche l'exige explicitement. Quand vous consultez des fichiers, précisez lesquels dans votre message ou votre PR.

## Descriptions courtes des fichiers dans `src/`

- `src/client/init.client.luau`: point d'entrée client, initialise les modules côté client.
- `src/client/camera/FPSCamera.luau`: contrôles et logique de la caméra FPS.
- `src/client/debug/Noclip.luau`: outil de debug pour activer/désactiver le noclip.
- `src/client/input/InputModule.luau`: gestion des entrées utilisateur et mapping des actions.
- `src/client/systems/BhopSystem.luau`: implémentation du bunnyhop (saut en chaîne).
- `src/client/systems/CoyoteJump.luau`: gestion du "coyote time" pour les sauts.
- `src/client/systems/CrouchSystem.luau`: logique de position accroupie et hitbox.
- `src/client/systems/GroundDetection.luau`: détection du sol et transitions air/sol.
- `src/client/systems/MovementController.luau`: contrôles de mouvement principaux (vitesse, acceleration).
- `src/client/systems/PhysicsStepAir.luau`: étape physique pour l'état en l'air.
- `src/client/systems/PhysicsStepGround.luau`: étape physique pour l'état au sol.
- `src/client/systems/SlopeSystem.luau`: gestion des pentes et adaptation du mouvement.
- `src/client/systems/StepupSystem.luau`: logique pour monter sur de petits obstacles.
- `src/client/systems/WallSlide.luau`: comportement de glisse le long des murs.
- `src/client/ui/SettingsMenu.luau`: interface des réglages côté client.
- `src/client/ui/Speedometer.luau`: affichage de la vitesse du joueur.
- `src/server/init.server.luau`: point d'entrée serveur, initialise les services côté serveur.
- `src/server/SettingsStore.luau`: stockage et récupération des paramètres serveur.
- `src/server/Validator.luau`: routines de validation côté serveur (anti-cheat, sanity checks).
- `src/shared/MovementConfig.luau`: constantes et paramètres de configuration du mouvement.
- `src/shared/MovementState.luau`: structure d'état partagée pour le mouvement du joueur.
- `src/shared/NetworkProtocol.luau`: définitions des messages et du protocole réseau.
- `src/shared/PhysicsUtils.luau`: fonctions utilitaires pour la physique.

## Common Commands

```bash
rojo serve
rojo build -o "CSGO.rbxlx"
```
