local GameAssetPaths = {}

GameAssetPaths.Root = {}

GameAssetPaths.Animations = {
	Bosses = { "Animations", "Bosses" },
	Combat = { "Animations", "Combat" },
}

GameAssetPaths.Models = {
	BodyParts = { "Models", "BodyParts" },
	Bosses = { "Models", "Bosses" },
	Gear = { "Models", "Gear" },
	HeadAccessories = { "Models", "HeadAccessories" },
	Worlds = {
		BossArenas = { "Models", "Worlds", "BossArenas" },
	},
}

GameAssetPaths.Effects = {
	Bosses = { "Effects", "Bosses" },
	Auras = { "Effects", "Auras" },
	Mutations = { "Effects", "Mutations" },
	Screen = { "Effects", "Screen" },
}

GameAssetPaths.Tools = {
	Potions = { "Tools", "Potions" },
}

GameAssetPaths.Audio = {
	Combat = { "Audio", "Combat" },
	Footsteps = { "Audio", "Footsteps" },
}

GameAssetPaths.UI = {
	Index = { "UI", "Index" },
	Icons = { "UI", "Icons" },
	RollCutscene = { "UI", "RollCutscene" },
}

GameAssetPaths.Legacy = {
	Animations = { "Animations" },
	Auras = { "Auras" },
	BodyParts = { "BodyParts" },
	BossArenas = { "BossArenas" },
	Bosses = { "Bosses" },
	MutationVFX = { "MutationVFX" },
	Potions = { "Potions" },
	ScreenEffects = { "ScreenEffects" },
	UI = { "UI" },
	VFX = { "VFX" },
}

return GameAssetPaths
