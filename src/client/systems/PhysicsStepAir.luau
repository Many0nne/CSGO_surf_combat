local PhysicsUtils = require(game:GetService("ReplicatedStorage").Shared.PhysicsUtils)
local Config       = require(game:GetService("ReplicatedStorage").Shared.MovementConfig)

local PhysicsStepAir = {}

-- Applique l'acceleration aerienne Source (air strafe, sans friction).
-- Opera sur le XZ uniquement : la gravite reste seule sur Y.
-- Si wishdir s'oppose a la velocite courante (dot < 0) -> friction braking XZ, Y preserve.
function PhysicsStepAir.step(velocity: Vector3, wishdir: Vector3, wishspeed: number, dt: number): Vector3
    if wishdir.Magnitude < 1e-4 then
        return velocity
    end
    local xz = PhysicsUtils.getXZ(velocity)
    local newXZ = PhysicsUtils.accelerate(xz, wishdir, wishspeed, Config.AIR_ACCEL, dt)
    return PhysicsUtils.setXZ(velocity, newXZ)
end

return PhysicsStepAir
