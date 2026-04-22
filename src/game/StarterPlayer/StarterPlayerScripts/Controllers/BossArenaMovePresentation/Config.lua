local Config = {
	Place = {
		ActiveProfileId = "boss_arena",
	},
	Remotes = {
		RootFolderName = "Remotes",
		BossArenaFolderName = "BossArena",
		MovePresentationRemoteName = "BossMovePresentation",
	},
	Folders = {
		VisualFolderName = "BossMoveClientEffects",
	},
	Shake = {
		ImpactMagnitude = 1.15,
		ImpactRoughness = 11,
		ImpactFadeIn = 0.03,
		ImpactFadeOut = 0.2,
	},
	Gui = {
		AcidBreathPoisonGuiName = "AcidBreathPoisonScreenEffect",
		AcidBreathPoisonBlurName = "AcidBreathPoisonBlur",
	},
	FireBurst = {
		RingDiameterPerSizeStud = 85,
	},
	SquidCall = {
		CannonAssetYawOffsetRadians = math.rad(90),
	},
}

return Config
