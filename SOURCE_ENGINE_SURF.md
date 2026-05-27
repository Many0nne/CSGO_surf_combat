# Source Engine (CS:GO) movement and surf

This document describes how the Valve Source movement system works (as used by CS:GO), with a focus on surf behavior. It is based on the Source SDK 2013 public code (CGameMovement) and known Source movement primitives. CS:GO is not open source, but its movement logic is a close descendant of the same codebase.

Primary references:
- Source SDK 2013 `gamemovement.cpp` (CGameMovement): https://raw.githubusercontent.com/ValveSoftware/source-sdk-2013/master/src/game/shared/gamemovement.cpp
- Source SDK 2013 `gamemovement.h` (CGameMovement API and constants): https://raw.githubusercontent.com/ValveSoftware/source-sdk-2013/master/src/game/shared/gamemovement.h

## 1. High-level movement pipeline

Source movement is handled by `CGameMovement::ProcessMovement` which calls `PlayerMove()`. The pipeline is roughly:

1) `CheckParameters()`
- clamps input move speeds to `mv->m_flMaxSpeed` and applies surface speed factors

2) `CategorizePosition()`
- determines if the player is on ground, on a ladder, in water, etc.
- identifies standable surfaces by checking plane normal Z (>= 0.7)

3) `FullWalkMove()` for `MOVETYPE_WALK`
- handles ground vs air
- applies friction and acceleration
- performs `WalkMove()` when grounded and `AirMove()` when not grounded

4) `TryPlayerMove()`
- resolves collisions via multi-plane clipping ("slide" along surfaces)

5) `FinishGravity()` and `CheckFalling()`
- gravity finalization and landing effects

The key mechanic for surf is how `CategorizePosition()` decides whether a plane is walkable, and how `TryPlayerMove()`/`ClipVelocity()` resolve collisions when the plane is too steep.

## 2. Walkable surface threshold (slope limit)

Source decides whether a surface is walkable based on the Z component of the plane normal:

- if `plane.normal.z >= 0.7` then it is considered a floor
- else it is considered too steep (not walkable)

This threshold corresponds to about 45 degrees:

$$\theta = \arccos(0.7) \approx 45.57^\circ$$

When the surface is too steep, the player is not grounded and movement continues as air movement with collision clipping. This is the core of surf: the player is effectively in-air but constrained by collision response against the ramp.

Source reference: `CategorizePosition()` and `TryTouchGroundInQuadrants()` in `gamemovement.cpp`.

## 3. Ground movement model (friction + acceleration)

When grounded, Source applies friction and then accelerates toward a wish direction.

### Friction (ground)
`Friction()` uses `sv_friction` and `sv_stopspeed`:

- speed = |velocity|
- control = max(speed, sv_stopspeed)
- drop = control * sv_friction * frametime
- newSpeed = max(speed - drop, 0)
- velocity *= newSpeed / speed

This friction only applies when a ground entity exists.

### Acceleration (ground)
`Accelerate()` performs the classic Source/Quake style acceleration:

- currentSpeed = dot(velocity, wishdir)
- addSpeed = wishspeed - currentSpeed
- accelSpeed = accel * frametime * wishspeed * surfaceFriction
- accelSpeed = min(accelSpeed, addSpeed)
- velocity += wishdir * accelSpeed

This is why strafing and good angle control can build speed in Source-like movement.

## 4. Air movement model (air accelerate)

`AirMove()` builds the wish direction from view angles and input, then uses `AirAccelerate()` with `sv_airaccelerate`:

- wishdir from forward/right vectors, Z set to 0
- wishspeed clamped to max speed
- `AirAccelerate()` uses `GetAirSpeedCap()` (default 30 units/s) to cap wishspeed
- apply acceleration similarly to ground but with `sv_airaccelerate`

Even in air, velocity changes are constrained by this accel equation, so air control depends on maintaining a good angle between wishdir and velocity.

## 5. Collision response: ClipVelocity and surf

The heart of surf is the collision response code in `TryPlayerMove()` and `ClipVelocity()`:

- `TryPlayerMove()` attempts to move along velocity for the frame
- if a collision occurs, it collects plane normals and repeatedly clips velocity against those planes
- clipping removes the velocity component into the plane (and optionally bounces)

`ClipVelocity(in, normal, out, overbounce)`:

- backoff = dot(in, normal) * overbounce
- out = in - normal * backoff
- adjust again if out still points into the plane

For walk movement, surf ramps are not walkable, so the player is not grounded. The physics thus uses air movement + collision clipping against the ramp plane. The ramp plane normal removes the perpendicular component, leaving a tangential velocity that slides along the ramp. Gravity continues to act, adding velocity down the slope.

This is essentially a "sliding along plane" behavior.

## 6. Why surf works

Surf emerges from three facts:

1) Steep ramps are not ground
- `plane.normal.z < 0.7` => player not grounded

2) Air movement has no ground friction
- only air accelerate applies

3) Collision response projects velocity along the ramp
- `ClipVelocity()` removes the normal component, leaving tangential motion

Combined, the player can ride the ramp with little speed loss, only losing speed to air control limits and minor collision adjustments. Gravity accelerates the player down the ramp, often adding speed when the direction is aligned.

## 7. Overbounce, ramps, and speed gain

`ClipVelocity()` takes an `overbounce` factor. For standard walk movement, it is typically 1.0, but can be larger on bouncy surfaces. The overbounce slightly changes the energy preserved along the ramp plane. In surf, most servers keep normal bounce behavior (no extra energy), but the projection plus gravity can still increase speed.

## 8. Important convars (movement tuning)

The Source movement system is heavily influenced by server convars:

- `sv_friction` (ground friction)
- `sv_stopspeed` (minimum speed used for friction computation)
- `sv_accelerate` (ground accel)
- `sv_airaccelerate` (air accel)
- `sv_maxvelocity` (hard cap for velocity)

In CS:GO, many surf servers customize these values to exaggerate air control and allow high speeds. The core behavior, however, still comes from the standard CGameMovement code path.

## 9. Summary (surf-specific)

- Walkable ground is defined by `normal.z >= 0.7` (about 45.6 degrees).
- Surf ramps are too steep, so the player is considered in-air.
- While in-air, movement uses air acceleration and gravity.
- Collision response clips velocity against the ramp, leaving tangential motion.
- This combination causes the classic surf glide with controllable strafes.

## 10. Notes on CS:GO specifics

CS:GO uses Source but has game-specific tweaks (CSTRIKE_DLL blocks in `gamemovement.cpp`). The overall surf mechanics still follow the same core functions:

- `CategorizePosition()` for ground detection
- `AirMove()`/`AirAccelerate()` for in-air control
- `TryPlayerMove()` + `ClipVelocity()` for sliding along surfaces

Because these core methods are the same as Source SDK 2013, the explanations above are accurate for the general behavior of CS:GO surf movement. Exact constants (like accel and friction defaults) can differ per game build or server config.
