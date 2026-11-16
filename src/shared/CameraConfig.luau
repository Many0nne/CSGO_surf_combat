-- Alignement en colonnes conservé volontairement
-- stylua: ignore
return {
	DEFAULT_FOV       = 90,
	DEFAULT_SENS      = 0.10, -- degrés par pixel de souris
	SENS_MIN          = 0.01,
	SENS_MAX          = 1.0,
	PITCH_MIN         = -89,
	PITCH_MAX         = 89,
	CAM_HEIGHT_STAND  = 2.5,
	CAM_HEIGHT_CROUCH = 1.2,
	CAM_LERP_SPEED    = 12,
	SCOPE_SENS_MULT   = 1.0,  -- × ratio du zoom (ScopeSensitivity) : 1 = même vitesse à l'écran qu'au hip-fire
	SCOPE_SENS_MIN    = 0.5,
	SCOPE_SENS_MAX    = 2.0,
	GAMEPAD_TURN_RATE = 260,  -- degrés/s au stick droit à fond, sensibilité manette 1 (#276)
	GAMEPAD_SENS      = 1.0,  -- multiplicateur réglable de la visée au stick
	GAMEPAD_SENS_MIN  = 0.2,
	GAMEPAD_SENS_MAX  = 3.0,
	TOUCH_LOOK_MULT   = 2.0,  -- × sensibilité souris pour un glisser au doigt (px)
}
