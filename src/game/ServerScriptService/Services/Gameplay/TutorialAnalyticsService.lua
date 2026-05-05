local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Diagnostics.Logger)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local TUTORIAL_VERSION = "v2"

local ONBOARDING_STEPS = table.freeze({
	[1] = "Tutorial Eligible",
	[2] = "Tutorial Started",
	[3] = "First Roll Completed",
	[4] = "First Body Part Equipped / Tutorial Complete",
	[5] = "Rolling Lesson: Paid Roll Used",
	[6] = "Rolling Lesson: Clean+ Rolled",
	[7] = "Rolling Lesson: Clean+ Equipped",
	[8] = "Man Aura Lesson: Man Set Completed",
	[9] = "Man Aura Lesson: Man Aura Equipped",
	[10] = "Appraisal Tour: Appraiser Met",
	[11] = "Appraisal Tour: Body Part Appraised",
	[12] = "Crafting Tour: Crafter Met",
	[13] = "Crafting Tour: Crown Recipe Opened",
	[14] = "Crafting Tour: Crown Crafted",
	[15] = "Boss World Tour: Boss World Entered",
	[16] = "Boss World Tour: First Boss Defeated",
	[17] = "Boss World Tour: First Gear Crafted",
})

local ONBOARDING_QUEST_PART_STEPS = table.freeze({
	stan_paid_roll_intro = table.freeze({
		[1] = 5,
		[2] = 6,
		[3] = 7,
	}),
	stan_man_aura_intro = table.freeze({
		[1] = 8,
		[2] = 9,
	}),
	stan_appraisal_intro = table.freeze({
		[1] = 10,
		[2] = 11,
	}),
	stan_crafting_intro = table.freeze({
		[1] = 12,
		[2] = 13,
		[3] = 14,
	}),
	stan_boss_intro = table.freeze({
		[1] = 15,
		[2] = 16,
		[3] = 17,
	}),
})

local loggedStepsByPlayer: { [Player]: { [number]: boolean } } = {}

local TutorialAnalyticsService = {}

local function isLoggableTutorialState(state: any): boolean
	return typeof(state) == "table" and state.completed ~= true and state.adminReplay ~= true
end

local function buildInitialCustomFields()
	local activeProfile = PlaceProfile.GetActiveProfile()
	return {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = "unknown_platform",
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = activeProfile.id,
		[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = TUTORIAL_VERSION,
	}
end

function TutorialAnalyticsService:LogOnboardingStep(player: Player, stepNumber: number, tutorialState: any?)
	if player.Parent ~= Players then
		return
	end
	if tutorialState ~= nil and not isLoggableTutorialState(tutorialState) then
		return
	end

	local normalizedStepNumber = math.floor(tonumber(stepNumber) or 0)
	local stepName = ONBOARDING_STEPS[normalizedStepNumber]
	if stepName == nil then
		Logger.Warn(string.format("[TutorialAnalyticsService] Unknown onboarding step %s.", tostring(stepNumber)))
		return
	end

	local loggedSteps = loggedStepsByPlayer[player]
	if loggedSteps == nil then
		loggedSteps = {}
		loggedStepsByPlayer[player] = loggedSteps
	end
	if loggedSteps[normalizedStepNumber] == true then
		return
	end
	loggedSteps[normalizedStepNumber] = true

	task.spawn(function()
		if player.Parent ~= Players then
			return
		end

		local customFields = if normalizedStepNumber == 1 then buildInitialCustomFields() else nil
		local ok, err = pcall(function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, normalizedStepNumber, stepName, customFields)
		end)
		if not ok then
			Logger.Warn(string.format(
				"[TutorialAnalyticsService] Failed to log onboarding step %d (%s): %s",
				normalizedStepNumber,
				stepName,
				tostring(err)
			))
		end
	end)
end

function TutorialAnalyticsService:LogOnboardingQuestPartCompleted(player: Player, questId: string, partIndex: number)
	if typeof(questId) ~= "string" or questId == "" then
		return
	end

	local questSteps = ONBOARDING_QUEST_PART_STEPS[questId]
	if typeof(questSteps) ~= "table" then
		return
	end

	local normalizedPartIndex = math.floor(tonumber(partIndex) or 0)
	local stepNumber = questSteps[normalizedPartIndex]
	if typeof(stepNumber) ~= "number" then
		return
	end

	self:LogOnboardingStep(player, stepNumber, nil)
end

function TutorialAnalyticsService:LogBossWorldGuidePrompted(player: Player)
end

function TutorialAnalyticsService:LogBossWorldGuideCompleted(player: Player)
end

function TutorialAnalyticsService:OnPlayerRemoving(player: Player)
	loggedStepsByPlayer[player] = nil
end

return TutorialAnalyticsService
