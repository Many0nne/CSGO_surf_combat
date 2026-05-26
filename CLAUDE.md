# CSGO

## Overview

Projet Rojo qui synchronise une expérience Roblox depuis l'arborescence `src/`.

## Current Structure

```text
CSGO/
  aftman.toml
  default.project.json
  README.md
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

## Notes

- Garder `default.project.json` synchronisé avec l'arborescence `src/` (mappings Rojo).
- `aftman.toml` gère la version de Rojo utilisée.
- `SPEC.md` contient la spécification détaillée (mappings, architecture, constantes). Utilisez-le comme source de vérité pour la structure des fichiers.

## Common Commands

```bash
rojo serve
rojo build -o "CSGO.rbxlx"
```
