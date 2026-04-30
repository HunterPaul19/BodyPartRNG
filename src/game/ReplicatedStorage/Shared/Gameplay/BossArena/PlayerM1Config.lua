local PlayerM1Config = {
	Damage = 20,
	CooldownSeconds = 0.55,
	HitboxDurationSeconds = 0.12,
	WidthScale = 1.75,
	HeightScale = 1.35,
	DepthScale = 2.6,
	ForwardOffsetScale = 0.65,
	HitboxHeightStuds = 100,
	MaxParts = 48,
	ScreenShakeMagnitude = 0.35,
	ScreenShakeRoughness = 10,
	ScreenShakeFadeIn = 0.02,
	ScreenShakeFadeOut = 0.12,
	AnimationFadeSeconds = 0.08,
	AnimationPriority = Enum.AnimationPriority.Action4,
}

return table.freeze(PlayerM1Config)
