local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DataController = require(script.Parent.DataController)
local ObjectiveGuideController = require(script.Parent.ObjectiveGuideController)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local Schema = require(ReplicatedStorage.Lists.Schema)

local LOCAL_PLAYER = Players.LocalPlayer
local MAIN_PROFILE_ID = "main"
local GUIDE_ID = "boss_world_guide"
local QUESTS_KEY = Schema.Quests and Schema.Quests.key or "quests"
local STAN_BOSS_INTRO_QUEST_ID = "stan_boss_intro"
local GUIDE_TEXT = "Boss world unlocked. Go to the portal."
local TARGET_PATH = "Workspace.BossPortal"
local PROMPT_TAG = "EnterBossLobbyPortalPrompt"

local BossWorldGuideController = {
	_started = false,
	_active = false,
	_gui = nil :: ScreenGui?,
	_label = nil :: TextLabel?,
}

local function shouldRunForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == MAIN_PROFILE_ID
end

local function shouldShow(rawQuestState: any): boolean
	if typeof(rawQuestState) ~= "table" then
		return false
	end

	local activeByQuestId = rawQuestState.activeByQuestId
	local activeQuest = if typeof(activeByQuestId) == "table" then activeByQuestId[STAN_BOSS_INTRO_QUEST_ID] else nil
	if typeof(activeQuest) ~= "table" or activeQuest.status ~= "active" then
		return false
	end

	return math.floor(tonumber(activeQuest.currentPartIndex) or 1) <= 1
end

local function resolveBossPortalPromptTarget(): Instance?
	for _, instance in ipairs(CollectionService:GetTagged(PROMPT_TAG)) do
		if instance:IsA("ProximityPrompt") and instance:IsDescendantOf(Workspace) then
			local promptParent = instance.Parent
			return if promptParent and promptParent:IsA("BasePart") then promptParent else instance
		end
	end

	return nil
end

function BossWorldGuideController:_ensureGui()
	if self._gui and self._gui.Parent then
		return
	end

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BossWorldGuideGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 950
	gui:SetAttribute("KeepEnabledDuringHatch", true)
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromScale(0.5, 0.16)
	frame.Size = UDim2.fromScale(0.5, 0.045)
	frame.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "Prompt"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Size = UDim2.fromScale(1, 1)
	label.Text = GUIDE_TEXT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextTransparency = 1
	label.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Name = "NOSCALE"
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1.25
	stroke.Transparency = 0.25
	stroke.Parent = label

	self._gui = gui
	self._label = label
end

function BossWorldGuideController:_show()
	self:_ensureGui()

	if self._label then
		self._label.Text = GUIDE_TEXT
		self._label.TextTransparency = 0
	end
	if self._gui then
		self._gui.Enabled = true
	end

	ObjectiveGuideController.ShowObjective(GUIDE_ID, resolveBossPortalPromptTarget() or TARGET_PATH, {
		fallbackTargetPath = "Workspace.BossPortal.Hitbox",
		projectTargetToGround = false,
	})
	self._active = true
end

function BossWorldGuideController:_hide()
	if self._label then
		self._label.TextTransparency = 1
	end
	if self._gui then
		self._gui.Enabled = false
	end

	ObjectiveGuideController.ClearObjective(GUIDE_ID)
	self._active = false
end

function BossWorldGuideController:_syncFromData(data: any)
	local rawQuestState = if typeof(data) == "table" then data[QUESTS_KEY] else nil
	if shouldShow(rawQuestState) then
		self:_show()
	else
		self:_hide()
	end
end

function BossWorldGuideController:OnStart()
	if self._started then
		return
	end

	self._started = true
	if not shouldRunForPlace() then
		return
	end

	if DataController.Loaded == true then
		self:_syncFromData(DataController:Get())
	end
	DataController.DataReceived:Connect(function(data: any)
		self:_syncFromData(data)
	end)
	DataController.DataUpdated:Connect(function(key: string)
		if key == QUESTS_KEY then
			self:_syncFromData(DataController:Get())
		end
	end)
end

return BossWorldGuideController
