# CS:GO Movement System — Roblox/Rojo Spec

## Context

Implémentation fidèle du système de mouvement CS:GO (Source Engine / Quake III physics) dans Roblox via Rojo, pour 1-8 joueurs simultanés. Le projet est un init Rojo vide. Toute la physique est custom (override du Humanoid), avec rendu caméra FPS. La cible est une expérience bhop/strafe sans cap de vitesse (style bhop servers), avec des mécaniques sol fidèles à Source.

---

## Décisions de Design

| Question             | Décision                                                            |
| -------------------- | ------------------------------------------------------------------- |
| Bhop speed cap       | **Aucun cap** (bhop/surf servers — vitesse peut croître infiniment) |
| Diagonales           | **Normalisées** (W+A = même vitesse que W seul)                     |
| Architecture réseau  | **Client authoritative + validation serveur légère**                |
| Crouch               | **Complet** (vitesse réduite + hitbox réduite + animation cam)      |
| Tick rate            | **60 Hz natif Roblox** (RunService.Heartbeat, dt réel)              |
| Feedback HUD         | **Speedometer** numérique bas/centre (style KZ)                     |
| Pentes               | **Source slope physics** — seuil 45°, slide au-dessus               |
| Valeurs jump/gravité | **Ajustées pour le feel Roblox** (pas de conversion exacte)         |
| Character base       | **Humanoid PlatformStand + CFrame manual**                          |
| Ground detection     | **Shapecast** (cylindre sous le character)                          |
| Strafe skill floor   | **Légèrement assisté** (tolérance d'angle élargie vs CS:GO pur)     |
| Animations           | **State machine manuelle** (run/walk/jump/crouch/air)               |
| Wall collision       | **Wallslide** (projection sur normale du mur)                       |
| Net sync fréquence   | **~20 Hz** (tous les 3 ticks)                                       |
| Anti-cheat serveur   | Speed hack + position delta + noclip detection                      |
| Camera settings      | **Menu in-game** (Escape)                                           |
| Coyote time          | **Oui — ~80-100ms**                                                 |
| Jump buffer          | **Oui — ~100-150ms**                                                |
| Walk (Shift)         | **Hold uniquement**                                                 |
| Air crouch           | **Autorisé** (hitbox réduite immédiate)                             |
| Ladders              | **Hors scope**                                                      |
| Speedometer format   | Chiffre simple `284 u/s`, bas centre                                |
| Auto-bhop            | **Option toggle** (config flag)                                     |
| Recul en l'air (S)   | **Stop quasi-immédiat** (1-2 frames)                                |
| Pente seuil slide    | **> 45°**                                                           |
| Settings persistence | **DataStore Roblox**                                                |
| Stepup               | **Oui — ~18 studs max**                                             |
| Spawn                | **SpawnLocation Roblox standard**                                   |
| Noclip dev tool      | **Oui** (Studio uniquement, commande)                               |

---

## Architecture Technique

### Rojo Mapping
```
src/client/   → StarterPlayerScripts/Client
src/server/   → ServerScriptService/Server
src/shared/   → ReplicatedStorage/Shared
```

### Structure des Fichiers

```
src/
  client/
    init.client.luau              — Bootstrap : crée le character custom, bind events
    systems/
      MovementController.luau     — Boucle principale (Heartbeat), state machine
      GroundDetection.luau        — Shapecast descendant, sol + normale + pente angle
      PhysicsStepGround.luau      — Friction, accélération sol, wishdir
      PhysicsStepAir.luau         — Air acceleration, strafe, backward stop
      BhopSystem.luau             — Timing atterrissage, friction skip, auto-bhop
      CrouchSystem.luau           — State crouch, hitbox resize, camera lerp
      SlopeSystem.luau            — Slide sur pentes > 45°, projection vitesse
      StepupSystem.luau           — Détection + montée petites marches
      WallSlide.luau              — Projection vitesse sur normale de mur
      CoyoteJump.luau             — Timer coyote, jump buffer
    camera/
      FPSCamera.luau              — Scriptable, MouseDelta, yaw/pitch, FOV
    input/
      InputModule.luau            — UserInputService, état WASD+Shift+Space+Ctrl
    ui/
      Speedometer.luau            — ScreenGui, TextLabel, mise à jour chaque frame
      SettingsMenu.luau           — Escape menu, sens + FOV sliders, DataStore save
    debug/
      Noclip.luau                 — Commande /noclip (Studio uniquement)
  server/
    init.server.luau              — Bootstrap serveur
    Validator.luau                — Validation speed/position delta/noclip
    SettingsStore.luau            — DataStore sens/FOV par joueur
  shared/
    MovementConfig.luau           — Toutes les constantes physiques
    PhysicsUtils.luau             — dot, normalize, clamp, projectOnPlane, etc.
    MovementState.luau            — Enum des états
    NetworkProtocol.luau          — Format des RemoteEvents
```

---

## Constantes Physiques (MovementConfig.luau)

```lua
RUN_SPEED          = 16       -- ~250 Source u/s
WALK_SPEED         = 8        -- ~52% run
CROUCH_SPEED       = 4.5

-- Accélération
GROUND_ACCEL       = 128      -- ground accelerate
AIR_ACCEL          = 50       -- air accelerate (Source-style, scaled by wishspeed)
AIR_SPEED_CAP      = 40       -- équivalent GetAirSpeedCap() Source
FRICTION           = 8.0      -- surface friction
STOP_SPEED         = 2

-- Saut / Gravité
JUMP_VELOCITY      = 38
GRAVITY            = -125     -- u/s² (ajusté pour le feel Roblox)
MAX_FALL_SPEED     = 100

-- Pentes
SLOPE_ANGLE_MAX    = 45
STEPUP_HEIGHT      = 1.2      -- ~18 Source units en studs
SLOPE_FRICTION     = 0.1

-- Bhop
BHOP_LAND_WINDOW   = 0.1      -- secondes : fenêtre bon timing
AUTO_BHOP          = true     -- flag toggle (par défaut activé)

-- Coyote / buffer
COYOTE_TIME        = 0.09     -- 90ms
JUMP_BUFFER_TIME   = 0.13     -- 130ms

-- STRAFE_ASSIST_DEG = 45     -- tolérance angle supplémentaire (actuellement désactivé)

-- Réseau
NET_SYNC_RATE      = 20       -- Hz
MAX_SPEED_SERVER   = 300      -- cap validation (haut pour bhop libre)
MAX_DELTA_POS      = 5        -- studs max entre deux updates

-- Caméra
DEFAULT_FOV        = 90
DEFAULT_SENS       = 0.3
PITCH_MIN, PITCH_MAX = -89, 89
CAM_HEIGHT_STAND   = 2.5
CAM_HEIGHT_CROUCH  = 1.2
CAM_LERP_SPEED     = 12

-- Hitbox
CHAR_RADIUS        = 1.0
CHAR_HEIGHT_STAND  = 4.8
CHAR_HEIGHT_CROUCH = 2.4
```

---

## Mécaniques Physiques

### Mouvement au Sol (formule Source)

```
1. wishdir = normalize(inputDir)
2. Friction :
     drop = speed * FRICTION * dt
     velocity.XZ *= max(0, speed - drop) / speed
3. wishspeed selon état (run / walk / backward max)
4. Accélération :
     addSpeed = wishspeed - dot(velocity.XZ, wishdir)
     if addSpeed > 0:
       accelSpeed = min(GROUND_ACCEL * wishspeed * dt, addSpeed)
       velocity.XZ += accelSpeed * wishdir
```

### Mouvement Aérien & Air Strafe

```
- Modèle Source : airWishspeed = min(wishspeed, AIR_SPEED_CAP)
- addSpeed = airWishspeed - dot(velocity.XZ, wishdir)
- accelSpeed = min(AIR_ACCEL * airWishspeed * dt, addSpeed)
- Pas de friction en l'air
- Clamp MAX_FALL_SPEED uniquement hors surf
- Strafe : wishdir = lookVector.XZ rotated par A/D
           gain si angle(velocity, wishdir) < 90° + STRAFE_ASSIST_DEG
```

### Bunny Hop

```
À l'atterrissage :
  if saut buffered dans JUMP_BUFFER_TIME → skip friction, sauter
  
À chaque tick sol :
  if jumpPressed (ou jumpHeld si AUTO_BHOP) :
    bon timing (≤ BHOP_LAND_WINDOW) → friction skippée → jump
    mauvais timing → friction normale → jump
```

### Crouch

- Hold Ctrl → state CROUCHING
- Hitbox resize immédiate (Y : STAND → CROUCH)
- Caméra lerp vers CAM_HEIGHT_CROUCH (speed = 12)
- Air crouch autorisé, hitbox immédiate
- Uncrouch bloqué si shapecast haut détecte obstacle

### Pentes & Stepup

- Pente ≤ 45° : wishdir projeté sur plan de surface (`projectOnPlane`)
- Pente > 45° : state SLIDING — gravité projetée sur pente, wishdir ignoré
- Stepup ≤ 1.2 studs : si bloqué horizontal → cast haut + avant → CFrame ajusté

### Wallslide

- Collision mur → `velocity = projectOnPlane(velocity, wallNormal)`
- Vitesse tangentielle conservée
- La normale surf est conservée uniquement si on se dirige vers la rampe

---

## Caméra FPS

```lua
-- RenderStepped :
local delta = UserInputService:GetMouseDelta()
yaw   += delta.X * sensitivity
pitch  = math.clamp(pitch - delta.Y * sensitivity, PITCH_MIN, PITCH_MAX)
Camera.CFrame = headCFrame
  * CFrame.Angles(0, math.rad(-yaw), 0)
  * CFrame.Angles(math.rad(-pitch), 0, 0)
```

- `Camera.CameraType = Enum.CameraType.Scriptable`
- `MouseBehavior = LockCenter`
- `lookVector.XZ` = référentiel du strafe aérien

---

## Architecture Réseau

**Client → Serveur (20 Hz) :**
```
SyncPosition { position, velocity, state, tick }
```

**Validation serveur :**
1. `|velocity.XZ| > MAX_SPEED_SERVER` → warn/kick
2. `|pos_new - pos_last| > MAX_DELTA_POS * dt * 60` → reject + correction
3. Spherecast à pos_new dans géométrie solide → reject + correction

**Serveur → Client :** `PositionCorrection` si invalide

---

## State Machine

```
GROUNDED | AIRBORNE | SLIDING | CROUCHING_GROUND | CROUCHING_AIR

GROUNDED        → AIRBORNE          : not onGround
GROUNDED        → SLIDING           : slopeAngle > 45°
GROUNDED        → CROUCHING_GROUND  : Ctrl pressed
AIRBORNE        → GROUNDED          : onGround (→ bhop check)
AIRBORNE        → CROUCHING_AIR     : Ctrl pressed
SLIDING         → AIRBORNE          : saut
CROUCHING_*     → *                 : Ctrl released + espace libre
```

---

## HUD & Settings

**Speedometer :** chiffre `284 u/s`, bas/centre, couleur selon vitesse relative (blanc/vert/jaune/rouge)

**Menu Settings (Escape) :**
- Sensibilité : slider 0.1 → 5.0
- FOV : slider 60 → 120
- Persistance : `DataStoreService:GetDataStore("PlayerSettings")` par UserId

---

## Out-of-Scope

- Ladders
- Sons de pas / headbob
- Wall running
- Water physics
- Weapons
- Anti-cheat avancé
- Mobile

---

## Risques & Tradeoffs

| Risque                                   | Mitigation                                          |
| ---------------------------------------- | --------------------------------------------------- |
| Roblox throttle RemoteEvents > ~20/s     | Sync volontairement limité à 20 Hz                  |
| Delta time variable (60 Hz non constant) | Physique scalée par dt réel                         |
| Interpolation autres joueurs             | Hors scope v1                                       |
| CFrame manual bypass collisions Roblox   | Collisions gérées manuellement (wallslide + stepup) |

---

## Plan d'Implémentation — Ordre de Priorité

> Règle : chaque étape est testable isolément avant de passer à la suivante.

### PHASE 1 — Fondations

**Étape 1 — Structure Rojo & Config**
- Créer tous les fichiers `.luau` (vides) selon la structure
- Remplir `MovementConfig.luau`, `PhysicsUtils.luau`, `MovementState.luau`
- Mettre à jour `default.project.json`
- **Test** : `rojo build` sans erreur

**Étape 2 — Character Controller**
- `init.client.luau` : CharacterAdded → Humanoid PlatformStand, désactiver Animate
- Stocker refs `HumanoidRootPart`, `Humanoid`
- **Test** : spawn sans contrôle par défaut

**Étape 3 — Ground Detection (Shapecast)**
- `GroundDetection.luau` : `getGroundInfo()` → `{ onGround, normal, slopeAngle, material }`
- Cylinder shapecast vers le bas, exclure le character
- **Test** : print `onGround` en sautant/atterrissant

### PHASE 2 — Mouvement au Sol

**Étape 4 — Input Module**
- `InputModule.luau` : WASD + Shift + Space + Ctrl
- `getWishDir(cameraYaw)` → Vector3 XZ normalisé
- **Test** : print wishdir selon les touches

**Étape 5 — Physique Sol (run/walk/stop/backward)**
- `PhysicsStepGround.luau` : friction + accélération Source
- Boucle Heartbeat dans `MovementController.luau`
- Gravité custom chaque tick
- **Test** : courir, s'arrêter, reculer (vitesse limitée)

**Étape 6 — Diagonales normalisées** *(dans getWishDir)*

**Étape 7 — Stepup**
- `StepupSystem.luau` : bloqué horizontal → cast haut + avant → CFrame Y ajusté
- **Test** : monter une marche ~1 stud automatiquement

**Étape 8 — Wallslide**
- `WallSlide.luau` : projection vitesse sur normale mur
- **Test** : courir à 45° contre un mur → glisser

**Étape 9 — Pentes**
- `SlopeSystem.luau` : ≤ 45° → wishdir projeté ; > 45° → SLIDING + gravité projetée
- **Test** : ramp 30° et ramp 60° en Studio

### PHASE 3 — Caméra FPS

**Étape 10 — Caméra FPS**
- `FPSCamera.luau` : Scriptable, LockCenter, yaw/pitch clampé
- Exporter `getCameraYaw()`
- **Test** : caméra tourne avec la souris

### PHASE 4 — Saut & Aérien

**Étape 11 — Saut de base**
- Jump velocity, transition GROUNDED → AIRBORNE
- **Test** : sauter, retomber

**Étape 12 — Coyote Time & Jump Buffer**
- `CoyoteJump.luau` : timer 90ms + jump buffer 130ms
- **Test** : sauter en bord de plateforme légèrement après

**Étape 13 — Mouvement Aérien & Air Strafe**
- `PhysicsStepAir.luau` : AIR_ACCEL, stop S rapide, strafe avec angle assist
- **Test** : strafe en l'air → vitesse croît sur speedometer embryonnaire

### PHASE 5 — Bunny Hop

**Étape 14 — Bhop**
- `BhopSystem.luau` : friction skip au bon tick, jump buffer intégré
- **Test** : bhop 5× → vitesse croît / mauvais timing → perte

**Étape 15 — Auto-bhop (flag)**
- `AUTO_BHOP = true` → bhop parfait en tenant Space
- **Test** : vitesse croît indéfiniment avec AUTO_BHOP

### PHASE 6 — Crouch

**Étape 16 — Crouch complet**
- `CrouchSystem.luau` : hitbox resize, cam lerp, vitesse réduite, air crouch, uncrouch bloqué
- **Test** : crouch sol/air, uncrouch sous plafond bloqué

### PHASE 7 — Animations

**Étape 17 — State Machine Animations**
- `AnimationTrack` depuis Humanoid selon l'état (idle/run/walk/jump/fall/crouch)
- **Test** : transitions visuelles correctes

### PHASE 8 — HUD & Settings

**Étape 18 — Speedometer**
- `Speedometer.luau` : chiffre bas/centre, couleur dynamique

**Étape 19 — Menu Settings**
- `SettingsMenu.luau` : sliders sens + FOV (Escape)

**Étape 20 — Persistance DataStore**
- `SettingsStore.luau` : save/load par UserId via RemoteFunction
- **Test** : rejoindre → quitter → rejoindre → settings restaurés

### PHASE 9 — Réseau & Anti-Cheat

**Étape 21 — Sync Position 20 Hz**
- RemoteEvent `SyncPosition` toutes les 3 ticks

**Étape 22 — Validation Serveur**
- `Validator.luau` : 3 checks → `PositionCorrection` si invalide

### PHASE 10 — Dev Tools & Polish

**Étape 23 — Noclip Dev Tool**
- `Noclip.luau` : commande `/noclip`, Studio uniquement

**Étape 24 — Polish & Calibration**
- Ajustement des constantes pour le feel final
- Tests edge cases bhop/strafe/crouch/slope

---

## Vérification End-to-End

1. `rojo build -o "CSGO.rbxlx"` → pas d'erreur
2. Roblox Studio + plugin Rojo → `rojo serve`
3. Playtest Solo :
   - Run/walk/backward, diagonales
   - Saut, coyote, jump buffer
   - Bhop 5× → speedometer croît
   - Air strafe → speedometer croît
   - S en l'air → arrêt rapide
   - Crouch sol/air/uncrouch bloqué
   - Pente 30° et 60°, stepup, wallslide
4. Playtest Multi (2 clients) : sync + anti-cheat
5. DataStore : modifier sens → quitter → rejoindre → restauré
