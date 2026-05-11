local GameAssetPaths = {}

GameAssetPaths.Root = {}

GameAssetPaths.Animations = {
	Bosses = { "Animations", "Bosses" },
	Combat = { "Animations", "Combat" },
}

GameAssetPaths.Models = {
	BodyParts = { "Models", "BodyParts" },
	Bosses = { "Models", "Bosses" },
	Chests = { "Models", "Chests" },
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
	Chests = { "Audio", "Chests" },
	Combat = { "Audio", "Combat" },
	Footsteps = { "Audio", "Footsteps" },
}

GameAssetPaths.UI = {
	Index = { "UI", "Index" },
	Icons = { "UI", "Icons" },
	PlayerOverhead = { "UI", "PlayerOverhead" },
	RollCutscene = { "UI", "RollCutscene" },
	ScreenDarkener = { "UI", "ScreenDarkener" },
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
