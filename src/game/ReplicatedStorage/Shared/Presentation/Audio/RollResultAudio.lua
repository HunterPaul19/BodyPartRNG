local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Diagnostics.Logger)
local SoundUtil = require(script.Parent.SoundUtil)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local RollingConfig = require(ReplicatedStorage.Shared.Config.RollingConfig)
local RollCutsceneConfig = require(ReplicatedStorage.Shared.UI.RollCutsceneConfig)

local RollResultAudio = {}

local CUTSCENE_SIMPLER_SOUND_NAME = "RNG Cutscene Achievement Simpler"
local CUTSCENE_COMPLEX_SOUND_NAME = "RNG Cutscene Achievement Complex"

local MUTATION_SOUND_NAME_BY_ID = table.freeze({
	diamond = "RNG Diamond Mutation",
	magma = "RNG Magma Mutation",
	corrupted = "RNG Corrupted",
	prismatic = "RNG Prismatic",
})

local RARITY_SOUND_NAME_BY_DISPLAY_RARITY = table.freeze({
	Basic = "RNG Rarity Basic",
	Clean = "RNG Rarity Clean",
	Prime = "RNG Rarity Prime",
	Elite = "RNG Rarity Elite",
	Apex = "Apex",
})

local function resolveMutationSoundName(rollInfo): string?
	if typeof(rollInfo) ~= "table" then
		return nil
	end

	local mutationId = MutationConfig.NormalizeId(rollInfo.MutationId or rollInfo.Mutation)
	if mutationId == MutationConfig.GetDefault().id then
		return nil
	end

	return MUTATION_SOUND_NAME_BY_ID[mutationId]
end

local function resolveRaritySoundName(rollInfo): string?
	if typeof(rollInfo) ~= "table" then
		return nil
	end

	local displayRarity = RollingConfig.NormalizeDisplayRarity(rollInfo.Rarity)
	return RARITY_SOUND_NAME_BY_DISPLAY_RARITY[displayRarity]
end

local function resolveCutsceneSoundName(rollResult, rollInfo): string?
	local cutsceneTier = if typeof(rollResult) == "table" then tonumber(rollResult.cutsceneTier) else nil
	if cutsceneTier == nil then
		cutsceneTier = RollCutsceneConfig.ResolveTier(if typeof(rollInfo) == "table" then rollInfo.Rarity else nil)
	end

	local roundedTier = math.floor(cutsceneTier or 0)
	if roundedTier >= RollCutsceneConfig.TierByRarity.Elite then
		return CUTSCENE_COMPLEX_SOUND_NAME
	end
	if roundedTier >= RollCutsceneConfig.TierByRarity.Clean then
		return CUTSCENE_SIMPLER_SOUND_NAME
	end

	return nil
end

function RollResultAudio.PlayCutscene(rollResult, rollInfo, parent: Instance?): Sound?
	local soundName = resolveCutsceneSoundName(rollResult, rollInfo)
	if not soundName then
		return nil
	end

	local sound = SoundUtil.Play(soundName, parent)
	if not sound then
		Logger.Warn(string.format("[RollResultAudio] Cutscene sound %q could not be resolved.", soundName))
	end

	return sound
end

function RollResultAudio.GetCutsceneDuration(rollResult, rollInfo, fallbackDuration: number?): number?
	local soundName = resolveCutsceneSoundName(rollResult, rollInfo)
	if not soundName then
		return fallbackDuration
	end

	local soundDuration = SoundUtil.GetDuration(soundName)
	if soundDuration then
		return soundDuration
	end

	return fallbackDuration
end

function RollResultAudio.PlayRarity(rollInfo, parent: Instance?): Sound?
	local soundName = resolveRaritySoundName(rollInfo)
	if not soundName then
		return nil
	end

	return SoundUtil.Play(soundName, parent)
end

function RollResultAudio.StartMutationLoop(rollInfo, parent: Instance?): Sound?
	local soundName = resolveMutationSoundName(rollInfo)
	if not soundName then
		return nil
	end

	return SoundUtil.PlayLooped(soundName, parent)
end

function RollResultAudio.StopMutationLoop(sound: Sound?)
	SoundUtil.Stop(sound)
end

return table.freeze(RollResultAudio)
