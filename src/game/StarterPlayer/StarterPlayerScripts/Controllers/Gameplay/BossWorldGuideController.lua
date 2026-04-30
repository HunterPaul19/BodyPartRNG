local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataController = require(script.Parent.DataController)
local ObjectiveGuideController = require(script.Parent.ObjectiveGuideController)
local BossWorldGuideState = require(ReplicatedStorage.Shared.Character.BossWorldGuideState)
local TutorialState = require(ReplicatedStorage.Shared.Character.TutorialState)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local Schema = require(ReplicatedStorage.Lists.Schema)

local LOCAL_PLAYER = Players.LocalPlayer
local MAIN_PROFILE_ID = "main"
local GUIDE_ID = "boss_world_guide"
local BOSS_WORLD_GUIDE_KEY = Schema.BossWorldGuide and Schema.BossWorldGuide.key or nil
local TUTORIAL_KEY = Schema.Tutorial and Schema.Tutorial.key or nil
local GUIDE_TEXT = "Boss world unlocked. Go to the portal."
local TARGET_PATH = "Workspace.BossPortal"

local BossWorldGuideController = {
	_started = false,
	_active = false,
	_gui = nil :: ScreenGui?,
	_label = nil :: TextLabel?,
}

local function shouldRunForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == MAIN_PROFILE_ID
end

local function shouldShow(rawGuideState: any, rawTutorialState: any): boolean
	local guideState = BossWorldGuideState.Normalize(rawGuideState)
	return TutorialState.IsCompleted(rawTutorialState)
		and guideState.prompted == true
		and guideState.completed ~= true
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

	ObjectiveGuideController.ShowObjective(GUIDE_ID, TARGET_PATH, {
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
	local rawGuideState = if typeof(data) == "table" then data[BOSS_WORLD_GUIDE_KEY] else nil
	local rawTutorialState = if typeof(data) == "table" then data[TUTORIAL_KEY] else nil
	if shouldShow(rawGuideState, rawTutorialState) then
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
	if not BOSS_WORLD_GUIDE_KEY or not shouldRunForPlace() then
		return
	end

	if DataController.Loaded == true then
		self:_syncFromData(DataController:Get())
	end
	DataController.DataReceived:Connect(function(data: any)
		self:_syncFromData(data)
	end)
	DataController.DataUpdated:Connect(function(key: string)
		if key == BOSS_WORLD_GUIDE_KEY or key == TUTORIAL_KEY then
			self:_syncFromData(DataController:Get())
		end
	end)
end

return BossWorldGuideController
