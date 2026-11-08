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
}
