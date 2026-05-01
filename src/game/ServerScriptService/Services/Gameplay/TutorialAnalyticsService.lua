local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Diagnostics.Logger)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local TUTORIAL_VERSION = "v1"

local ONBOARDING_STEPS = table.freeze({
	[1] = "Tutorial Eligible",
	[2] = "Tutorial Started",
	[3] = "First Roll Completed",
	[4] = "First Body Part Equipped / Tutorial Complete",
	[13] = "Boss World Guide Prompted",
	[14] = "Boss World Entered",
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

function TutorialAnalyticsService:LogBossWorldGuidePrompted(player: Player)
	self:LogOnboardingStep(player, 13, nil)
end

function TutorialAnalyticsService:LogBossWorldGuideCompleted(player: Player)
	self:LogOnboardingStep(player, 14, nil)
end

function TutorialAnalyticsService:OnPlayerRemoving(player: Player)
	loggedStepsByPlayer[player] = nil
end

return TutorialAnalyticsService
