local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local GUIControls = {}

GUIControls.AutoRoll = false
GUIControls.CurrentlyRolling = false
GUIControls.RollDebounce = false
GUIControls.RollingState = nil
GUIControls.SuppressRollClickUntil = 0
GUIControls.IsDropdownOpen = false
GUIControls.LastSelectRequestId = 0
GUIControls.DropdownInteractionId = 0
GUIControls.DropdownAnimationId = 0
GUIControls.AutoRollLoopId = 0
GUIControls.AutoRollScheduleId = 0
GUIControls.CurrentRollResult = nil
GUIControls.CurrentRollResultEquipped = false
GUIControls.EquipDebounce = false
GUIControls.EquipStatusToken = 0
GUIControls.StatusRefreshToken = 0
GUIControls.RollingStateRefreshPending = false
GUIControls.RollPreviewSessionId = 0
GUIControls.ActiveRollPreviewSessionId = nil
GUIControls.ActiveMutationLoopSound = nil
GUIControls.RollCooldownUntil = 0
GUIControls.RollPresentationPending = false

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GroupService = game:GetService("GroupService")

local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local RollResultAudio = require(ReplicatedStorage.Shared.Audio.RollResultAudio)
local ToggleSoundUtil = require(ReplicatedStorage.Shared.Audio.ToggleSoundUtil)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local PreviewAppearanceRegistry = require(ReplicatedStorage.Shared.Character.PreviewAppearanceRegistry)
local RollTargetRegions = require(ReplicatedStorage.Shared.Character.RollTargetRegions)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local RollWarningNotifier = require(ReplicatedStorage.Shared.UI.RollWarningNotifier)
local RollCutscene = require(ReplicatedStorage.Shared.UI.RollCutscene)
local RollCutsceneConfig = require(ReplicatedStorage.Shared.UI.RollCutsceneConfig)
local ScreenEffects = require(ReplicatedStorage.Shared.UI.ScreenEffects)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)

local LocalPlayer = Players.LocalPlayer

local REMOTE_WAIT_TIMEOUT = 15

local function requireChild(parent: Instance, childName: string, className: string): Instance
	local child = parent:FindFirstChild(childName)
	if child == nil then
		child = parent:WaitForChild(childName, REMOTE_WAIT_TIMEOUT)
	end

	local expectedPath = string.format("%s.%s", parent:GetFullName(), childName)
	if child == nil then
		Logger.Error(string.format(
			"[Roll.GUIControls] Timed out after %d seconds waiting for %s.",
			REMOTE_WAIT_TIMEOUT,
			expectedPath
		), 0)
	end

	if not child:IsA(className) then
		Logger.Error(string.format(
			"[Roll.GUIControls] Expected %s to be a %s, got %s.",
			expectedPath,
			className,
			child.ClassName
		), 0)
	end

	return child
end

local Remotes = requireChild(ReplicatedStorage, "Remotes", "Folder")
local RollingRemotes = requireChild(Remotes, "Rolling", "Folder")
local GetRollingStateRemote = requireChild(RollingRemotes, "GetRollingState", "RemoteFunction") :: RemoteFunction
local SelectRollTypeRemote = requireChild(RollingRemotes, "SelectRollType", "RemoteFunction") :: RemoteFunction
local SelectRollRegionRemote = requireChild(RollingRemotes, "SelectRollRegion", "RemoteFunction") :: RemoteFunction
local PerformRollRemote = requireChild(RollingRemotes, "PerformRoll", "RemoteFunction") :: RemoteFunction
local ToggleQuickRollRemote = requireChild(RollingRemotes, "ToggleQuickRoll", "RemoteFunction") :: RemoteFunction
local ToggleAutoEquipBestRemote = requireChild(RollingRemotes, "ToggleAutoEquipBest", "RemoteFunction") :: RemoteFunction
local PromptQuickRollPurchaseRemote = requireChild(RollingRemotes, "PromptQuickRollPurchase", "RemoteFunction") :: RemoteFunction
local FinalizeAutoSellRollRemote = requireChild(RollingRemotes, "FinalizeAutoSellRoll", "RemoteFunction") :: RemoteFunction
local RollingUpdatedRemote = requireChild(RollingRemotes, "RollingUpdated", "RemoteEvent") :: RemoteEvent
local BODY_PARTS_FOLDER_NAME = "BodyParts"
local EQUIP_REMOTE_NAME = "EquipOwnedBodyPart"

local Main = script.Parent
local Black2 = Main.Parent.Black2
local DisplayFrame = Main:WaitForChild("DisplayFrame")
local SubInfoFrame = Main:WaitForChild("SubInfo")
local MainButtons = Main.Parent.Main
local RollButton = MainButtons.RollButton
local QuickRollButton = MainButtons.QuickRoll
local AutoRollButton = MainButtons.AutoRoll
local AutoEquipBestButton = MainButtons:WaitForChild("AutoEquipBestButton")
local AutoEquipBestUsageLabel = AutoEquipBestButton:WaitForChild("Usage")
local AutoEquipBestSelectionCorners = AutoEquipBestUsageLabel:FindFirstChild("SelectionCorners")
local RollDropdown = RollButton.RollDropdown
local RollDropdownInner = RollDropdown.Inner
local RollDropdownScrollingFrame = RollDropdownInner.ScrollingFrame
local RollDropdownTemplate = RollDropdownScrollingFrame.Template
local RollIcon = RollButton.Icon
local RollShadowIcon = RollButton.ShadowIcon
local DropdownButton = RollButton.DropdownButton
local LeftButton = RollButton.Left
local RightButton = RollButton.Right
local DEFAULT_ROLL_DESC_COLOR = RollButton.Desc.TextColor3
local READY_ROLL_DESC_COLOR = Color3.fromRGB(255, 223, 94)
local AUTO_EQUIP_BEST_ACTIVE_COLOR = Color3.fromRGB(96, 226, 98)
local DEFAULT_AUTO_EQUIP_BEST_BACKGROUND_COLOR = AutoEquipBestButton.BackgroundColor3
local DEFAULT_AUTO_EQUIP_BEST_IMAGE_COLOR = if AutoEquipBestButton:IsA("ImageButton")
	then AutoEquipBestButton.ImageColor3
	else Color3.new(1, 1, 1)
local DEFAULT_AUTO_EQUIP_BEST_TEXT_COLOR = if AutoEquipBestUsageLabel:IsA("TextLabel")
	then AutoEquipBestUsageLabel.TextColor3
	else Color3.new(1, 1, 1)
local DEFAULT_AUTO_EQUIP_BEST_CORNER_FRAME_COLORS = {}
if AutoEquipBestSelectionCorners then
	for _, descendant in ipairs(AutoEquipBestSelectionCorners:GetDescendants()) do
		if descendant:IsA("Frame") then
			table.insert(DEFAULT_AUTO_EQUIP_BEST_CORNER_FRAME_COLORS, {
				frame = descendant,
				color = descendant.BackgroundColor3,
			})
		end
	end
end
local RollResultRaritySubInfoLabel = SubInfoFrame:FindFirstChild("Rarity")
local RollResultMutationSubInfoLabel = SubInfoFrame:FindFirstChild("Mutation")
local EverRolledSubInfoLabel = SubInfoFrame:FindFirstChild("EverRolled")
local DEFAULT_SUBINFO_RARITY_TEXT = if RollResultRaritySubInfoLabel and RollResultRaritySubInfoLabel:IsA("TextLabel")
	then RollResultRaritySubInfoLabel.Text
	else ""
local DEFAULT_SUBINFO_MUTATION_TEXT = if RollResultMutationSubInfoLabel and RollResultMutationSubInfoLabel:IsA("TextLabel")
	then RollResultMutationSubInfoLabel.Text
	else ""
local DEFAULT_SUBINFO_EVER_ROLLED_TEXT = if EverRolledSubInfoLabel and EverRolledSubInfoLabel:IsA("TextLabel")
	then EverRolledSubInfoLabel.Text
	else "N/A Ever Rolled"
local DEFAULT_SUBINFO_RARITY_VISUAL_STATE = nil
local DEFAULT_SUBINFO_MUTATION_VISUAL_STATE = nil

local Blur = Instance.new("BlurEffect")
Blur.Parent = game.Lighting
Blur.Name = "RollBlur"
Blur.Size = 0

local GROUP_ID = 384839595
local BASE_ROLL_COOLDOWN = 1
local BASE_SEQUENCE_DURATION = 2.5
local BASE_AUTO_RESULT_HOLD = 0.8
local AUTO_ROLL_MIN_RETRY_DELAY = 0.05
local PREVIEW_SEQUENCE_LENGTH = 10
local ROLL_NOTIFICATION_HOLD_KEY = "rollResult"
local BasePosition = UDim2.fromScale(0.5, 0.358)
local OffsetPosition = BasePosition + UDim2.fromScale(0, 0.1)
local DropdownTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local DropdownClosedPosition = UDim2.fromScale(0.5, 2)
local DropdownOpenPosition = UDim2.fromScale(0.5, 0.5)
local ROLL_TICK_SOUND_NAME = "RollTickSound"

local CooldownFrameTween = TweenService:Create(
	RollButton.CooldownFrame,
	TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	{ BackgroundTransparency = 0.3 }
)

local ShowBlackTween = TweenService:Create(Black2, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.8 })
local HideBlackTween = TweenService:Create(Black2, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
local BlurTween = TweenService:Create(Blur, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = 10 })
local UnblurTween = TweenService:Create(Blur, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = 0 })
local DisplayTween = TweenService:Create(Main.DisplayFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0.63) })
local DisplayViewportTween = TweenService:Create(Main.DisplayFrame.ViewportFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, -0.5) })
local SubInfoTween = TweenService:Create(Main.SubInfo, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0.5, 0.5) })

local function formatMoney(value)
	return "$" .. NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function formatRollIncomePerSecond(value)
	local formattedIncome = BodyPartPresentation.FormatMoneyPerSecond(math.max(0, tonumber(value) or 0))
	return (formattedIncome:gsub("/s$", "/S"))
end

local function formatWholeNumber(value)
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function formatRollResultEverRolledText(serialNumber)
	local resolvedSerialNumber = math.floor(tonumber(serialNumber) or 0)
	if resolvedSerialNumber <= 0 then
		return "N/A Ever Rolled"
	end

	return string.format("#%s Ever Rolled", NumberFormatter.Format(resolvedSerialNumber))
end

local function cloneSupportedTextAdornment(instance: Instance): Instance?
	if instance:IsA("UIGradient") or instance:IsA("UIStroke") then
		return instance:Clone()
	end

	return nil
end

local function clearSupportedTextAdornments(label: TextLabel)
	for _, child in ipairs(label:GetChildren()) do
		if child:IsA("UIGradient") or child:IsA("UIStroke") then
			child:Destroy()
		end
	end
end

local function captureTextLabelVisualState(label: TextLabel?): any
	if not (label and label:IsA("TextLabel")) then
		return nil
	end

	local adornments = {}
	for _, child in ipairs(label:GetChildren()) do
		local clonedAdornment = cloneSupportedTextAdornment(child)
		if clonedAdornment then
			table.insert(adornments, clonedAdornment)
		end
	end

	return {
		text = label.Text,
		fontFace = label.FontFace,
		textColor3 = label.TextColor3,
		textStrokeColor3 = label.TextStrokeColor3,
		textStrokeTransparency = label.TextStrokeTransparency,
		richText = label.RichText,
		adornments = adornments,
	}
end

local function restoreTextLabelVisualState(label: TextLabel?, state: any)
	if not (label and label:IsA("TextLabel") and typeof(state) == "table") then
		return
	end

	label.Text = if typeof(state.text) == "string" then state.text else label.Text
	if typeof(state.fontFace) == "Font" then
		label.FontFace = state.fontFace
	end
	if typeof(state.textColor3) == "Color3" then
		label.TextColor3 = state.textColor3
	end
	if typeof(state.textStrokeColor3) == "Color3" then
		label.TextStrokeColor3 = state.textStrokeColor3
	end
	if typeof(state.textStrokeTransparency) == "number" then
		label.TextStrokeTransparency = state.textStrokeTransparency
	end
	if typeof(state.richText) == "boolean" then
		label.RichText = state.richText
	end

	clearSupportedTextAdornments(label)
	for _, adornment in ipairs(state.adornments or {}) do
		local clonedAdornment = cloneSupportedTextAdornment(adornment)
		if clonedAdornment then
			clonedAdornment.Parent = label
		end
	end
end

DEFAULT_SUBINFO_RARITY_VISUAL_STATE = captureTextLabelVisualState(RollResultRaritySubInfoLabel)
DEFAULT_SUBINFO_MUTATION_VISUAL_STATE = captureTextLabelVisualState(RollResultMutationSubInfoLabel)

local function resetRollResultSubInfo()
	restoreTextLabelVisualState(RollResultRaritySubInfoLabel, DEFAULT_SUBINFO_RARITY_VISUAL_STATE)
	if RollResultRaritySubInfoLabel and RollResultRaritySubInfoLabel:IsA("TextLabel") then
		RollResultRaritySubInfoLabel.Text = DEFAULT_SUBINFO_RARITY_TEXT
	end

	restoreTextLabelVisualState(RollResultMutationSubInfoLabel, DEFAULT_SUBINFO_MUTATION_VISUAL_STATE)
	if RollResultMutationSubInfoLabel and RollResultMutationSubInfoLabel:IsA("TextLabel") then
		RollResultMutationSubInfoLabel.Text = DEFAULT_SUBINFO_MUTATION_TEXT
	end

	if EverRolledSubInfoLabel and EverRolledSubInfoLabel:IsA("TextLabel") then
		EverRolledSubInfoLabel.Text = DEFAULT_SUBINFO_EVER_ROLLED_TEXT
	end
end

local function formatLuckMultiplier(value)
	local numericValue = tonumber(value) or 1
	local roundedValue = math.floor((numericValue * 10) + 0.5) / 10
	return string.format("%.1fx", roundedValue)
end

local function formatLuckLabel(value)
	return string.format("%s Luck", formatLuckMultiplier(value))
end

local function formatSizeMultiplier(value)
	local numericValue = math.max(0, tonumber(value) or 1)
	local roundedHundredths = math.floor((numericValue * 100) + 0.5) / 100
	local roundedTenths = math.floor((roundedHundredths * 10) + 0.5) / 10
	if math.abs(roundedHundredths - roundedTenths) < 0.005 then
		return string.format("%.1fx", roundedTenths)
	end
	return string.format("%.2fx", roundedHundredths)
end

local function formatSizeLabel(sizeName, scale)
	local resolvedName = if typeof(sizeName) == "string" and sizeName ~= "" then sizeName else "Normal"
	return string.format("Size: %s (%s)", resolvedName, formatSizeMultiplier(scale))
end

local function shouldPlayRollCutscene(rollResult)
	if typeof(rollResult) ~= "table" then
		return false
	end

	return rollResult.shouldPlayCutscene == true
end

local function playRollCutsceneIfNeeded(rollResult, rollInfo, beforeReveal)
	if not shouldPlayRollCutscene(rollResult) or typeof(rollInfo) ~= "table" then
		if beforeReveal then
			beforeReveal()
		end
		return
	end

	local cutsceneColor = if typeof(rollInfo.Color) == "Color3" then rollInfo.Color else Color3.new(1, 1, 1)
	local tier = tonumber(rollResult.cutsceneTier) or RollCutsceneConfig.ResolveTier(rollInfo.Rarity)
	local didReveal = false
	local function revealOnce()
		if didReveal then
			return
		end

		didReveal = true
		if beforeReveal then
			beforeReveal()
		end
	end

	local cutsceneDuration = RollResultAudio.GetCutsceneDuration(rollResult, rollInfo, RollCutsceneConfig.DefaultDuration)
	RollResultAudio.PlayCutscene(rollResult, rollInfo)
	local ok, err = pcall(function()
		RollCutscene.Play(cutsceneColor, tier, cutsceneDuration, revealOnce)
	end)
	if not ok then
		Logger.Warn(string.format("[RollGUI] Roll cutscene failed: %s", tostring(err)))
	end
	revealOnce()
end

local function resolveRollResultMutationId(rollInfo)
	local currentRollResult = GUIControls.CurrentRollResult
	local candidateValues = {
		if typeof(currentRollResult) == "table" and typeof(currentRollResult.mutationResult) == "table"
			then currentRollResult.mutationResult.id
			else nil,
		if typeof(rollInfo) == "table" then rollInfo.MutationId else nil,
		if typeof(currentRollResult) == "table" and typeof(currentRollResult.finalResult) == "table"
			then currentRollResult.finalResult.MutationId
			else nil,
		if typeof(currentRollResult) == "table" and typeof(currentRollResult.ownedRecord) == "table"
			then currentRollResult.ownedRecord.mutationId
			else nil,
		if typeof(currentRollResult) == "table" and typeof(currentRollResult.ownedRecord) == "table"
			then currentRollResult.ownedRecord.mutation
			else nil,
		if typeof(rollInfo) == "table" then rollInfo.Mutation else nil,
	}

	for _, candidateValue in ipairs(candidateValues) do
		if typeof(candidateValue) == "string" and candidateValue ~= "" then
			return MutationConfig.NormalizeId(candidateValue)
		end
	end

	return MutationConfig.GetDefault().id
end

local function buildResolvedRollResultAudioInfo(rollInfo)
	if typeof(rollInfo) ~= "table" then
		return rollInfo
	end

	local resolvedMutationId = resolveRollResultMutationId(rollInfo)
	local resolvedRollInfo = table.clone(rollInfo)
	resolvedRollInfo.MutationId = resolvedMutationId
	if typeof(resolvedRollInfo.Mutation) ~= "string" or resolvedRollInfo.Mutation == "" then
		resolvedRollInfo.Mutation = MutationConfig.GetDisplayName(resolvedMutationId)
	end

	return resolvedRollInfo
end

local function stopActiveMutationLoop()
	RollResultAudio.StopMutationLoop(GUIControls.ActiveMutationLoopSound)
	GUIControls.ActiveMutationLoopSound = nil
end

local function playRollStartSound()
	SoundUtil.Play(ROLL_TICK_SOUND_NAME)
end

local function syncRollResultScreenEffect(rollInfo)
	ScreenEffects.HideAll()

	local presetName = MutationConfig.GetScreenEffectPreset(resolveRollResultMutationId(rollInfo))
	if typeof(presetName) == "string" and presetName ~= "" then
		ScreenEffects.Show(presetName)
	end
end

local function getSelectedRollType(state)
	if typeof(state) ~= "table" then
		return nil
	end

	if typeof(state.selectedRollType) == "table" then
		return state.selectedRollType
	end

	local selectedRollTypeId = state.selectedRollTypeId
	for _, rollType in ipairs(state.rollTypes or {}) do
		if rollType.selected or (selectedRollTypeId ~= nil and rollType.id == selectedRollTypeId) then
			return rollType
		end
	end

	return nil
end

local function getRollTypes(state)
	return (state and state.rollTypes) or {}
end

local function getRollRegions(state)
	return (state and state.rollRegions) or {}
end

local function hasCoreRollCollections(state)
	return #getRollTypes(state) > 0 and #getRollRegions(state) > 0
end

local function getSelectedRollRegion(state)
	if typeof(state) ~= "table" then
		return nil
	end

	local selectedRollRegion = state.selectedRollRegion
	for _, rollRegion in ipairs(state.rollRegions or {}) do
		if rollRegion.selected or (selectedRollRegion ~= nil and rollRegion.id == selectedRollRegion) then
			return rollRegion
		end
	end

	return nil
end

local function getRollRegionNotificationLabel(rollRegionId)
	local normalizedRegion = RollTargetRegions.Normalize(rollRegionId)
	if normalizedRegion == RollTargetRegions.FullBody then
		return "full body"
	end

	return string.lower(BodyPartPresentation.GetRegionLabel(normalizedRegion))
end

local function getQuickRollState(state)
	if typeof(state) ~= "table" or typeof(state.quickRoll) ~= "table" then
		return {
			owned = false,
			enabled = false,
		}
	end

	return state.quickRoll
end

local function getAutoEquipBestState(state)
	if typeof(state) ~= "table" or typeof(state.autoEquipBest) ~= "table" then
		return {
			enabled = false,
		}
	end

	return state.autoEquipBest
end

local function shouldPredictSkippedRollPresentation(triggerSource)
	return triggerSource == "auto" and getQuickRollState(GUIControls.RollingState).enabled == true
end

local function isPlayerInAutoRollGroup()
	local ok, inGroup = pcall(function()
		return LocalPlayer:IsInGroup(GROUP_ID)
	end)
	return ok and inGroup == true
end

local function invokeRemote(remote, payload)
	local ok, result = pcall(function()
		if payload ~= nil then
			return remote:InvokeServer(payload)
		end
		return remote:InvokeServer()
	end)
	if not ok then
		Logger.Warn(string.format("[RollGUI] Remote %s failed: %s", remote.Name, tostring(result)))
		return nil
	end
	return result
end

local function mergeRollingState(previousState, incomingState)
	if typeof(incomingState) ~= "table" then
		return previousState
	end

	if incomingState._isDelta ~= true or typeof(previousState) ~= "table" then
		return incomingState
	end

	local mergedState = table.clone(previousState)
	for key, value in pairs(incomingState) do
		if key ~= "_isDelta" then
			mergedState[key] = value
		end
	end

	return mergedState
end

local function getEquipOwnedBodyPartRemote()
	local bodyPartsFolder = Remotes:FindFirstChild(BODY_PARTS_FOLDER_NAME)
	if not (bodyPartsFolder and bodyPartsFolder:IsA("Folder")) then
		return nil
	end

	local equipRemote = bodyPartsFolder:FindFirstChild(EQUIP_REMOTE_NAME)
	if equipRemote and equipRemote:IsA("RemoteFunction") then
		return equipRemote
	end

	return nil
end

local function isInsufficientFundsMessage(message)
	return typeof(message) == "string"
		and string.find(string.lower(message), "need", 1, true) ~= nil
		and string.find(string.lower(message), "money", 1, true) ~= nil
end

local function isInventoryFullMessage(message)
	return typeof(message) == "string"
		and string.find(string.lower(message), "inventory is full", 1, true) ~= nil
end

local function showAutoCraftNotification(rollResult)
	if typeof(rollResult) ~= "table" or rollResult.autoCraftCommitted ~= true then
		return
	end

	Notify.Show(tostring(rollResult.autoCraftMessage or "Added roll to crafting."), {
		channel = "inventory",
		duration = 4,
		tone = "good",
	})
end

local function beginRollNotificationHold()
	if typeof(Notify.BeginHold) == "function" then
		Notify.BeginHold(ROLL_NOTIFICATION_HOLD_KEY)
	end
end

local function endRollNotificationHold()
	if typeof(Notify.EndHold) == "function" then
		Notify.EndHold(ROLL_NOTIFICATION_HOLD_KEY)
	end
end

local function clearViewport()
	ViewportModelRenderer.ClearRollPreview(DisplayFrame.ViewportFrame)
end

local previewPiecesByRegion = {}

local function getEligiblePreviewPieces(rollRegion)
	local normalizedRegion = RollTargetRegions.Normalize(rollRegion)
	local cached = previewPiecesByRegion[normalizedRegion]
	if cached then
		return cached
	end

	local eligiblePieces = if normalizedRegion == RollTargetRegions.FullBody
		then BodyPartsCatalog.GetRollEligiblePieces()
		else BodyPartsCatalog.GetRollEligiblePieces(normalizedRegion)

	previewPiecesByRegion[normalizedRegion] = eligiblePieces
	return eligiblePieces
end

local function buildClientRollInfoFromPiece(piece, overrides)
	if not piece then
		return nil
	end

	local setConfig = BodyPartsCatalog.GetSetForPiece(piece.id)
	if not setConfig then
		return nil
	end

	local mutationId = if typeof(overrides) == "table" and typeof(overrides.MutationId) == "string"
		then overrides.MutationId
		else MutationConfig.GetDefault().id
	local mutationData = MutationConfig.Get(mutationId) or MutationConfig.GetDefault()
	local sizeId = if typeof(overrides) == "table" and typeof(overrides.SizeId) == "string"
		then overrides.SizeId
		else SizeConfig.GetDefault().id
	local sizeScale = if typeof(overrides) == "table" and tonumber(overrides.SizeMultiplier) ~= nil
		then tonumber(overrides.SizeMultiplier)
		else SizeConfig.GetRepresentativeScale(sizeId)
	local sizeData = SizeConfig.Get(SizeConfig.NormalizeId(sizeId)) or SizeConfig.GetDefault()
	local finalCashPerSec = if typeof(overrides) == "table" and tonumber(overrides.CashPerSec) ~= nil
		then tonumber(overrides.CashPerSec)
		else tonumber(piece.passiveIncomePerSecond) or 0

	return {
		Name = setConfig.rollDisplay.displayName,
		BodyPart = piece.displayName,
		Region = piece.region,
		Chance = setConfig.rollDisplay.chance,
		CashPerSec = finalCashPerSec,
		FinalCashPerSec = finalCashPerSec,
		Color = setConfig.rollDisplay.color,
		Font = setConfig.rollDisplay.fontFace,
		Weight = setConfig.rollDisplay.fontWeight,
		Rarity = setConfig.rollDisplay.rarity,
		ApplyPlayerClothing = setConfig.applyPlayerClothing ~= false,
		ApplyPlayerBodyColors = setConfig.applyPlayerBodyColors ~= false,
		PieceId = piece.id,
		PieceDisplayName = piece.displayName,
		SetId = setConfig.id,
		SetDisplayName = setConfig.displayName,
		DisplayOddsDenominator = setConfig.rollDisplay.chance,
		SetBonusPassiveIncomePerSecond = setConfig.fullSetBonus.passiveIncomePerSecond,
		Mutation = mutationData.displayName,
		MutationId = mutationData.id,
		Size = sizeData.displayName,
		SizeId = sizeData.id,
		SizeMultiplier = sizeScale,
	}
end

local function buildClientPreviewSequence(rollResult)
	local finalResult = buildClientRollInfoFromPiece(
		rollResult and rollResult.finalResult and BodyPartsCatalog.GetPiece(rollResult.finalResult.PieceId),
		rollResult and rollResult.finalResult
	)
	if not finalResult then
		return nil
	end

	local eligiblePieces = getEligiblePreviewPieces(rollResult and rollResult.rollRegion)
	if #eligiblePieces == 0 then
		return { finalResult }
	end

	local randomSource = Random.new()
	local previewSequence = table.create(PREVIEW_SEQUENCE_LENGTH)
	for index = 1, PREVIEW_SEQUENCE_LENGTH - 1 do
		local previewPiece = eligiblePieces[randomSource:NextInteger(1, #eligiblePieces)]
		previewSequence[index] = buildClientRollInfoFromPiece(previewPiece)
	end
	previewSequence[PREVIEW_SEQUENCE_LENGTH] = finalResult
	return previewSequence
end

local function resolveRollInfoModel(rollInfo)
	if typeof(rollInfo) ~= "table" then
		return nil
	end

	if typeof(rollInfo.Model) == "Instance" then
		return rollInfo.Model
	end
	if typeof(rollInfo.PieceId) == "string" and rollInfo.PieceId ~= "" then
		return BodyPartsCatalog.ResolveBundleModel(rollInfo.PieceId)
	end

	return nil
end

local function renderRollInfo(rollInfo, sessionId)
	DisplayFrame.BundleName.Text = rollInfo.Name
	DisplayFrame.Chance.Text = "1 in " .. formatWholeNumber(rollInfo.Chance)
	if typeof(rollInfo.Color) == "Color3" then
		DisplayFrame.BundleName.TextColor3 = rollInfo.Color
	end
	if typeof(rollInfo.Font) == "Font" then
		DisplayFrame.BundleName.FontFace = rollInfo.Font
	end

	local appearanceSnapshot = PreviewAppearanceRegistry.GetSnapshotForUserId(LocalPlayer.UserId)
	local bundleModel = resolveRollInfoModel(rollInfo)
	if appearanceSnapshot ~= nil and typeof(rollInfo.Region) == "string" and rollInfo.Region ~= "" then
		ViewportModelRenderer.RenderBodyPartPreview(
			DisplayFrame.ViewportFrame,
			bundleModel,
			rollInfo.Region,
			appearanceSnapshot,
			rollInfo.SizeMultiplier,
			{
				applyPlayerClothing = rollInfo.ApplyPlayerClothing,
				applyPlayerBodyColors = rollInfo.ApplyPlayerBodyColors,
			},
			sessionId
		)
	else
		ViewportModelRenderer.RenderRollPreview(
			DisplayFrame.ViewportFrame,
			bundleModel,
			sessionId
		)
	end
end

local function restoreIdleRollUi()
	stopActiveMutationLoop()
	HideBlackTween:Play()
	UnblurTween:Play()
	ScreenEffects.HideAll()
	clearViewport()
	resetRollResultSubInfo()
	Main.Visible = false
	Main.SkipButton.Visible = false
	Main.SubInfo.Visible = false
	Main.EquipButton.Visible = false
	MainButtons.RollButton.Visible = true
	MainButtons.QuickRoll.Visible = true
	MainButtons.AutoRoll.Visible = true
	AutoEquipBestButton.Visible = true
	GUIControls.ActiveRollPreviewSessionId = nil
end

function GUIControls:BeginRollPreviewSession(): number
	GUIControls.RollPreviewSessionId += 1
	GUIControls.ActiveRollPreviewSessionId = GUIControls.RollPreviewSessionId

	return GUIControls.ActiveRollPreviewSessionId
end

function GUIControls:GetQuickRollEnabled()
	return getQuickRollState(GUIControls.RollingState).enabled == true
end

function GUIControls:GetRollCooldownDuration()
	local rollingState = GUIControls.RollingState
	if typeof(rollingState) == "table" then
		local effectiveCooldown = tonumber(rollingState.effectiveRollCooldown)
		if effectiveCooldown and effectiveCooldown > 0 then
			return effectiveCooldown
		end
	end

	return BASE_ROLL_COOLDOWN
end

function GUIControls:GetRollSequenceDuration()
	return BASE_SEQUENCE_DURATION
end

function GUIControls:GetAutoResultHoldDuration()
	return BASE_AUTO_RESULT_HOLD
end

function GUIControls:SetButtonVisualState(button, isActive, isEligible)
	local coverTransparency = if isActive then 0 else 0.07
	local strokeTransparency = if isActive then 0.15 else 0.52
	local textTransparency = if isEligible then 0 else 0.15

	if button:FindFirstChild("Cover") then
		button.Cover.ImageTransparency = coverTransparency
	end
	if button:FindFirstChild("Cover2") then
		button.Cover2.ImageTransparency = coverTransparency
	end
	if button:FindFirstChild("UIStroke") then
		button.UIStroke.Transparency = strokeTransparency
		button.UIStroke.Color = if isActive then Color3.fromRGB(96, 226, 98) else Color3.new(1, 1, 1)
	end
	if button:FindFirstChild("Content") then
		button.Content.TextTransparency = textTransparency
	end
	if button:FindFirstChild("Desc") then
		button.Desc.TextTransparency = textTransparency
	end
end

function GUIControls:RefreshQuickRollButton()
	local quickRollState = getQuickRollState(GUIControls.RollingState)
	QuickRollButton.Desc.Text = quickRollState.owned and (quickRollState.enabled and "On" or "Off") or "Gamepass Required"
	GUIControls:SetButtonVisualState(QuickRollButton, quickRollState.enabled == true, quickRollState.owned == true)
end

function GUIControls:RefreshAutoRollButton()
	local isEligible = isPlayerInAutoRollGroup()
	if not isEligible and GUIControls.AutoRoll then
		GUIControls.AutoRoll = false
		GUIControls.AutoRollLoopId += 1
	end

	AutoRollButton.Desc.Text = isEligible and (GUIControls.AutoRoll and "On" or "Off") or "Group Join Required"
	GUIControls:SetButtonVisualState(AutoRollButton, GUIControls.AutoRoll == true, isEligible)
end

function GUIControls:RefreshAutoEquipBestButton()
	local autoEquipBestState = getAutoEquipBestState(GUIControls.RollingState)
	local isEnabled = autoEquipBestState.enabled == true
	local color = if isEnabled then AUTO_EQUIP_BEST_ACTIVE_COLOR else DEFAULT_AUTO_EQUIP_BEST_IMAGE_COLOR

	AutoEquipBestButton.BackgroundColor3 = if isEnabled
		then AUTO_EQUIP_BEST_ACTIVE_COLOR
		else DEFAULT_AUTO_EQUIP_BEST_BACKGROUND_COLOR
	if AutoEquipBestButton:IsA("ImageButton") then
		AutoEquipBestButton.ImageColor3 = color
	end
	if AutoEquipBestUsageLabel:IsA("TextLabel") then
		AutoEquipBestUsageLabel.TextColor3 = if isEnabled
			then AUTO_EQUIP_BEST_ACTIVE_COLOR
			else DEFAULT_AUTO_EQUIP_BEST_TEXT_COLOR
	end
	for _, entry in ipairs(DEFAULT_AUTO_EQUIP_BEST_CORNER_FRAME_COLORS) do
		local frame = entry.frame
		if frame and frame.Parent and frame:IsA("Frame") then
			frame.BackgroundColor3 = if isEnabled then AUTO_EQUIP_BEST_ACTIVE_COLOR else entry.color
		end
	end
end

function GUIControls:SetAutoRollEnabled(enabled)
	local shouldEnable = enabled == true and isPlayerInAutoRollGroup()
	if GUIControls.AutoRoll == shouldEnable then
		GUIControls:InvalidateTemporaryStatus()
		GUIControls:RefreshRollControls()
		if shouldEnable and not GUIControls.CurrentlyRolling then
			GUIControls:ScheduleNextAutoRoll(AUTO_ROLL_MIN_RETRY_DELAY)
		end
		return
	end

	GUIControls.AutoRoll = shouldEnable
	GUIControls.AutoRollLoopId += 1
	GUIControls.AutoRollScheduleId += 1
	GUIControls:InvalidateTemporaryStatus()
	GUIControls:RefreshRollControls()

	if shouldEnable and not GUIControls.CurrentlyRolling then
		GUIControls:ScheduleNextAutoRoll(AUTO_ROLL_MIN_RETRY_DELAY)
	end
end

function GUIControls:GetAutoRollRetryDelay()
	local now = os.clock()
	local retryDelay = AUTO_ROLL_MIN_RETRY_DELAY

	if GUIControls.RollDebounce then
		local cooldownRemaining = GUIControls.RollCooldownUntil - now
		retryDelay = math.max(retryDelay, cooldownRemaining)
	end

	if GUIControls.CurrentlyRolling then
		retryDelay = math.max(retryDelay, AUTO_ROLL_MIN_RETRY_DELAY)
	end

	local suppressedRemaining = GUIControls.SuppressRollClickUntil - now
	if suppressedRemaining > 0 then
		retryDelay = math.max(retryDelay, suppressedRemaining)
	end

	return math.max(AUTO_ROLL_MIN_RETRY_DELAY, retryDelay)
end

function GUIControls:ScheduleNextAutoRoll(delayTime)
	if not GUIControls.AutoRoll then
		return
	end

	local loopId = GUIControls.AutoRollLoopId
	GUIControls.AutoRollScheduleId += 1
	local scheduleId = GUIControls.AutoRollScheduleId
	task.delay(math.max(0, tonumber(delayTime) or 0), function()
		if GUIControls.AutoRoll and loopId == GUIControls.AutoRollLoopId and scheduleId == GUIControls.AutoRollScheduleId then
			GUIControls:Roll("auto")
		end
	end)
end

function GUIControls:PromptAutoRollGroupJoin()
	local promptOpened, promptError = pcall(function()
		GroupService:PromptJoinAsync(GROUP_ID)
	end)
	if not promptOpened then
		GUIControls:SetTemporaryStatus(promptError or "Failed to open the group join prompt.")
		return
	end

	task.spawn(function()
		for _ = 1, 10 do
			task.wait(1)
			if isPlayerInAutoRollGroup() then
				GUIControls:SetAutoRollEnabled(true)
				return
			end
		end
		GUIControls:InvalidateTemporaryStatus()
		GUIControls:RefreshRollControls()
	end)
end

function GUIControls:InvalidateTemporaryStatus()
	GUIControls.StatusRefreshToken += 1
end

function GUIControls:SetTemporaryStatus(message)
	if typeof(message) ~= "string" or message == "" then
		return
	end

	GUIControls.StatusRefreshToken += 1
	local statusRefreshToken = GUIControls.StatusRefreshToken
	RollButton.Desc.TextColor3 = DEFAULT_ROLL_DESC_COLOR
	RollButton.Desc.Text = message
	task.delay(2, function()
		if statusRefreshToken == GUIControls.StatusRefreshToken and GUIControls.RollingState then
			GUIControls:RefreshRollControls()
		end
	end)
end

function GUIControls:SetEquipButtonText(text)
	local content = Main.EquipButton:FindFirstChild("Content")
	if content and content:IsA("TextLabel") then
		content.Text = tostring(text)
	end
end

function GUIControls:RefreshEquipButton()
	local ownedRecord = GUIControls.CurrentRollResult and GUIControls.CurrentRollResult.ownedRecord
	local hasOwnedResult = typeof(ownedRecord) == "table" and typeof(ownedRecord.ownedId) == "string" and ownedRecord.ownedId ~= ""
	local pendingAutoSellToken = GUIControls.CurrentRollResult and GUIControls.CurrentRollResult.pendingAutoSellToken
	local hasPendingAutoSellResult = typeof(pendingAutoSellToken) == "string" and pendingAutoSellToken ~= ""
	local shouldShow = Main.Visible and Main.SkipButton.Visible and Main.SubInfo.Visible and (hasOwnedResult or hasPendingAutoSellResult)
	local isEnabled = shouldShow and (not GUIControls.EquipDebounce) and (not GUIControls.CurrentRollResultEquipped)

	Main.EquipButton.Visible = shouldShow
	Main.EquipButton.Active = isEnabled
	Main.EquipButton.AutoButtonColor = isEnabled

	if GUIControls.EquipDebounce then
		GUIControls:SetEquipButtonText("Equipping...")
		GUIControls:SetButtonVisualState(Main.EquipButton, false, false)
		return
	end

	if GUIControls.CurrentRollResultEquipped then
		GUIControls:SetEquipButtonText("Equipped")
		GUIControls:SetButtonVisualState(Main.EquipButton, true, true)
		return
	end

	GUIControls:SetEquipButtonText(if hasPendingAutoSellResult then "Equip to Keep" else "Equip")
	GUIControls:SetButtonVisualState(Main.EquipButton, false, isEnabled)
	if shouldShow and not isEnabled then
		GUIControls:SetButtonVisualState(Main.EquipButton, false, false)
	end
end

function GUIControls:ShowEquipStatus(message, duration)
	if typeof(message) ~= "string" or message == "" then
		return
	end

	GUIControls.EquipStatusToken += 1
	local token = GUIControls.EquipStatusToken
	GUIControls:SetEquipButtonText(message)

	if tonumber(duration) and duration > 0 then
		task.delay(duration, function()
			if token == GUIControls.EquipStatusToken then
				GUIControls:RefreshEquipButton()
			end
		end)
	end
end

function GUIControls:EquipCurrentRollResult()
	if GUIControls.EquipDebounce or GUIControls.CurrentRollResultEquipped then
		return
	end

	local rollResult = GUIControls.CurrentRollResult
	local ownedRecord = rollResult and rollResult.ownedRecord
	local pendingAutoSellToken = rollResult and rollResult.pendingAutoSellToken
	local hasPendingAutoSellResult = typeof(pendingAutoSellToken) == "string" and pendingAutoSellToken ~= ""
	if not hasPendingAutoSellResult and (typeof(ownedRecord) ~= "table" or typeof(ownedRecord.ownedId) ~= "string" or ownedRecord.ownedId == "") then
		GUIControls:ShowEquipStatus("Equip unavailable", 1.5)
		return
	end

	local scale = tonumber(ownedRecord and ownedRecord.sizeMultiplier)
		or tonumber(rollResult and rollResult.finalResult and rollResult.finalResult.SizeMultiplier)
		or tonumber(rollResult and rollResult.sizeResult and rollResult.sizeResult.scale)
		or 1

	GUIControls.EquipDebounce = true
	GUIControls:RefreshEquipButton()

	local result
	if hasPendingAutoSellResult then
		result = invokeRemote(FinalizeAutoSellRollRemote, {
			token = pendingAutoSellToken,
			keep = true,
			equip = true,
			scale = scale,
		})
	else
		local equipRemote = getEquipOwnedBodyPartRemote()
		if not equipRemote then
			GUIControls.EquipDebounce = false
			GUIControls:RefreshEquipButton()
			GUIControls:ShowEquipStatus("Equip unavailable", 1.5)
			return
		end

		result = invokeRemote(equipRemote, {
			ownedId = ownedRecord.ownedId,
			scale = scale,
			applyVisuals = true,
		})
	end

	GUIControls.EquipDebounce = false
	if not result then
		GUIControls:RefreshEquipButton()
		GUIControls:ShowEquipStatus("Equip failed", 1.5)
		return
	end

	if result.ok ~= true then
		GUIControls:RefreshEquipButton()
		GUIControls:ShowEquipStatus(result.message or "Equip failed", 1.5)
		return
	end

	if typeof(result.state) == "table" then
		GUIControls:ApplyRollingState(result.state)
	end
	if hasPendingAutoSellResult and typeof(rollResult) == "table" then
		rollResult.pendingAutoSell = false
		rollResult.pendingAutoSellToken = nil
	end
	GUIControls:HideRollResults()
end

function GUIControls:SuppressRollClickForInputFrame()
	-- RollButton is the clickable parent container, so nested controls need to suppress
	-- the parent click briefly to avoid opening the dropdown and immediately rolling.
	GUIControls.SuppressRollClickUntil = os.clock() + 0.15
end

function GUIControls:SetButtonCooldown()
	local cooldownDuration = GUIControls:GetRollCooldownDuration()
	GUIControls.RollCooldownUntil = os.clock() + cooldownDuration
	GUIControls.RollDebounce = true
	RollButton.CooldownFrame.BackgroundTransparency = 1
	CooldownFrameTween:Play()
	RollButton.CooldownFrame.UIGradient.Offset = Vector2.new(0.5, 0)
	TweenService:Create(
		RollButton.CooldownFrame.UIGradient,
		TweenInfo.new(cooldownDuration, Enum.EasingStyle.Linear),
		{ Offset = Vector2.new(-0.5, 0) }
	):Play()
	task.delay(cooldownDuration, function()
		if os.clock() >= GUIControls.RollCooldownUntil - 0.01 then
			GUIControls.RollDebounce = false
		end
	end)
end

function GUIControls:SetDropdownOpen(isOpen)
	local shouldOpen = isOpen == true
	if GUIControls.IsDropdownOpen == shouldOpen then
		if shouldOpen then
			RollDropdown.Visible = true
		elseif GUIControls.DropdownAnimationId == 0 then
			RollDropdownInner.Position = DropdownClosedPosition
			DropdownButton.Rotation = 90
			RollDropdown.Visible = false
		end
		return
	end

	GUIControls.IsDropdownOpen = shouldOpen
	GUIControls.DropdownAnimationId += 1
	local animationId = GUIControls.DropdownAnimationId

	if shouldOpen then
		RollDropdown.Visible = true
		RollDropdownInner.Position = DropdownClosedPosition
		TweenService:Create(RollDropdownInner, DropdownTweenInfo, { Position = DropdownOpenPosition }):Play()
		TweenService:Create(DropdownButton, DropdownTweenInfo, { Rotation = 270 }):Play()
		return
	end

	local hideTween = TweenService:Create(RollDropdownInner, DropdownTweenInfo, { Position = DropdownClosedPosition })
	TweenService:Create(DropdownButton, DropdownTweenInfo, { Rotation = 90 }):Play()
	hideTween:Play()
	task.spawn(function()
		hideTween.Completed:Wait()
		if (not GUIControls.IsDropdownOpen) and animationId == GUIControls.DropdownAnimationId then
			RollDropdown.Visible = false
		end
	end)
end

function GUIControls:RefreshRollButton()
	local state = GUIControls.RollingState
	if not state then
		return
	end

	local selectedRollType = getSelectedRollType(state)
	local selectedRollRegion = getSelectedRollRegion(state)
	if not selectedRollType then
		return
	end

	local rollRegions = getRollRegions(state)
	local rollsSinceLuckyRoll = math.max(0, math.floor(tonumber(state.rollsSinceLuckyRoll) or 0))
	local luckyRollGoal = math.max(1, math.floor(tonumber(state.luckyRollGoal) or 10))
	local luckBoostReady = state.luckBoostReady == true
	local pityText = if luckBoostReady
		then "Lucky Roll Ready"
		else string.format("%s/%s", formatWholeNumber(rollsSinceLuckyRoll), formatWholeNumber(luckyRollGoal))
	local descColor = if luckBoostReady then READY_ROLL_DESC_COLOR else DEFAULT_ROLL_DESC_COLOR
	RollButton.TextLabel.Text =
		string.format('Roll <font color="rgb(96,226,98)">(%s)</font>', formatLuckMultiplier(selectedRollType.luckMultiplier))
	RollButton.Cost.Text = formatMoney(selectedRollType.moneyCost)
	RollButton.Desc.Text = pityText
	RollButton.Desc.TextColor3 = descColor
	if selectedRollRegion and typeof(selectedRollRegion.image) == "string" then
		RollIcon.Image = selectedRollRegion.image
		RollShadowIcon.Image = selectedRollRegion.image
	elseif typeof(state.selectedRollRegionIcon) == "string" and state.selectedRollRegionIcon ~= "" then
		RollIcon.Image = state.selectedRollRegionIcon
		RollShadowIcon.Image = state.selectedRollRegionIcon
	end
	if #rollRegions > 0 then
		LeftButton.Visible = #rollRegions > 1
		RightButton.Visible = #rollRegions > 1
	end
end

function GUIControls:RefreshRollControls()
	if GUIControls.RollingState then
		GUIControls:RefreshRollButton()
	end

	GUIControls:RefreshQuickRollButton()
	GUIControls:RefreshAutoRollButton()
	GUIControls:RefreshAutoEquipBestButton()
end

function GUIControls:PromptLockedRollType(rollType)
	Logger.Warn(string.format("[RollGUI] Purchase flow not implemented for locked roll type %s.", tostring(rollType.id)))
	GUIControls:SetTemporaryStatus(string.format("%s is locked.", tostring(rollType.displayName or rollType.id)))
end

function GUIControls:ApplyRollingState(state)
	if typeof(state) ~= "table" then
		return
	end

	local previousState = GUIControls.RollingState
	local mergedState = mergeRollingState(previousState, state)
	local shouldRebuildRollDropdown = state._isDelta ~= true or typeof(state.rollTypes) == "table"
	if state._isDelta == true and not hasCoreRollCollections(mergedState) then
		if typeof(previousState) == "table" then
			GUIControls.RollingState = previousState
		else
			GUIControls.RollingState = mergedState
		end

		if not GUIControls.RollingStateRefreshPending then
			GUIControls.RollingStateRefreshPending = true
			task.spawn(function()
				GUIControls:LoadRollingState()
			end)
		end
		return
	end

	GUIControls.RollingState = mergedState
	GUIControls.RollingStateRefreshPending = false
	GUIControls:InvalidateTemporaryStatus()
	if shouldRebuildRollDropdown then
		GUIControls:RebuildRollDropdown()
	end
	GUIControls:RefreshRollControls()
	if shouldRebuildRollDropdown and GUIControls.IsDropdownOpen then
		GUIControls:SetDropdownOpen(true)
	end
end

function GUIControls:SelectRollType(rollTypeId)
	GUIControls:SuppressRollClickForInputFrame()
	GUIControls.LastSelectRequestId += 1
	local requestId = GUIControls.LastSelectRequestId
	local interactionIdAtRequest = GUIControls.DropdownInteractionId
	local result = invokeRemote(SelectRollTypeRemote, { rollTypeId = rollTypeId })
	if requestId ~= GUIControls.LastSelectRequestId then
		return
	end
	if not result then
		GUIControls:SetTemporaryStatus("Failed to reach the server.")
		return
	end

	if not result.ok then
		GUIControls:SetTemporaryStatus(result.message or "Failed to select the roll type.")
		return
	end

	GUIControls:ApplyRollingState(result.state)
	GUIControls:InvalidateTemporaryStatus()
	GUIControls:RefreshRollControls()
	if interactionIdAtRequest == GUIControls.DropdownInteractionId then
		GUIControls:SetDropdownOpen(false)
	end
end

function GUIControls:SelectRollRegion(rollRegion)
	GUIControls:SuppressRollClickForInputFrame()
	local previousRollRegion = getSelectedRollRegion(GUIControls.RollingState)
	local result = invokeRemote(SelectRollRegionRemote, { rollRegion = rollRegion })
	if not result then
		GUIControls:SetTemporaryStatus("Failed to reach the server.")
		return
	end

	if not result.ok then
		GUIControls:SetTemporaryStatus(result.message or "Failed to select the roll region.")
		return
	end

	GUIControls:ApplyRollingState(result.state)
	GUIControls:InvalidateTemporaryStatus()
	GUIControls:RefreshRollControls()
	local currentRollRegion = getSelectedRollRegion(GUIControls.RollingState)
	if previousRollRegion and currentRollRegion and previousRollRegion.id ~= currentRollRegion.id then
		Notify.Show(string.format("Switched to rolling %s", getRollRegionNotificationLabel(currentRollRegion.id)))
	end
end

function GUIControls:CycleRollRegion(direction)
	GUIControls:SuppressRollClickForInputFrame()
	local state = GUIControls.RollingState
	local rollRegions = getRollRegions(state)
	if #rollRegions <= 1 then
		return
	end

	local selectedRollRegion = getSelectedRollRegion(state)
	if not selectedRollRegion then
		return
	end

	local currentIndex = 1
	for index, rollRegion in ipairs(rollRegions) do
		if rollRegion.id == selectedRollRegion.id then
			currentIndex = index
			break
		end
	end

	local nextIndex = ((currentIndex - 1 + direction) % #rollRegions) + 1
	GUIControls:SelectRollRegion(rollRegions[nextIndex].id)
end

function GUIControls:ToggleQuickRoll()
	local quickRollState = getQuickRollState(GUIControls.RollingState)
	if not quickRollState.owned then
		local result = invokeRemote(PromptQuickRollPurchaseRemote)
		if not result then
			GUIControls:SetTemporaryStatus("Failed to open the purchase prompt.")
			return
		end
		if typeof(result.state) == "table" then
			GUIControls:ApplyRollingState(result.state)
		end
		if not result.ok then
			GUIControls:SetTemporaryStatus(result.message or "Failed to open the purchase prompt.")
			return
		end
		GUIControls:InvalidateTemporaryStatus()
		GUIControls:RefreshRollControls()
		return
	end

	local result = invokeRemote(ToggleQuickRollRemote, { enabled = not quickRollState.enabled })
	if not result then
		GUIControls:SetTemporaryStatus("Failed to update Quick Roll.")
		return
	end
	if typeof(result.state) == "table" then
		GUIControls:ApplyRollingState(result.state)
	end
	if not result.ok then
		GUIControls:SetTemporaryStatus(result.message or "Failed to update Quick Roll.")
		return
	end

	GUIControls:InvalidateTemporaryStatus()
	GUIControls:RefreshRollControls()
	local updatedQuickRollState = getQuickRollState(GUIControls.RollingState)
	if updatedQuickRollState.enabled ~= quickRollState.enabled then
		ToggleSoundUtil.PlayToggle(updatedQuickRollState.enabled == true)
	end
end

function GUIControls:ToggleAutoEquipBest()
	local autoEquipBestState = getAutoEquipBestState(GUIControls.RollingState)
	local result = invokeRemote(ToggleAutoEquipBestRemote, { enabled = not autoEquipBestState.enabled })
	if not result then
		GUIControls:SetTemporaryStatus("Failed to update Auto Equip Best.")
		return
	end
	if typeof(result.state) == "table" then
		GUIControls:ApplyRollingState(result.state)
	end
	if not result.ok then
		GUIControls:SetTemporaryStatus(result.message or "Failed to update Auto Equip Best.")
		return
	end

	GUIControls:InvalidateTemporaryStatus()
	GUIControls:RefreshRollControls()
	local updatedAutoEquipBestState = getAutoEquipBestState(GUIControls.RollingState)
	if updatedAutoEquipBestState.enabled ~= autoEquipBestState.enabled then
		ToggleSoundUtil.PlayToggle(updatedAutoEquipBestState.enabled == true)
	end
end

function GUIControls:ToggleAutoRoll()
	if not isPlayerInAutoRollGroup() then
		GUIControls:PromptAutoRollGroupJoin()
		return
	end

	local previousAutoRoll = GUIControls.AutoRoll == true
	GUIControls:SetAutoRollEnabled(not GUIControls.AutoRoll)
	if GUIControls.AutoRoll ~= previousAutoRoll then
		ToggleSoundUtil.PlayToggle(GUIControls.AutoRoll == true)
	end
end

function GUIControls:RebuildRollDropdown()
	local state = GUIControls.RollingState
	for _, child in ipairs(RollDropdownScrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= RollDropdownTemplate then
			child:Destroy()
		end
	end

	RollDropdownTemplate.Visible = false

	for _, rollType in ipairs(getRollTypes(state)) do
		local entry = RollDropdownTemplate:Clone()
		entry.Name = rollType.id
		entry.LayoutOrder = rollType.uiOrder or 0
		entry.Visible = true
		entry.Parent = RollDropdownScrollingFrame

		local button = entry.Button
		button.TextLabel.Text = rollType.displayName
		button.Cost.Text = formatMoney(rollType.moneyCost)
		button.Luck.Text = formatLuckLabel(rollType.luckMultiplier)
		button.SelectedCover.Visible = rollType.selected == true
		button.ImageTransparency = 0
		button.AutoButtonColor = true
		button.TextLabel.TextTransparency = 0
		button.Cost.TextTransparency = 0
		button.Luck.TextTransparency = 0
		if button.TextLabel:FindFirstChild("UIStroke") then
			button.TextLabel.UIStroke.Transparency = 0
		end
		if button.Cost:FindFirstChild("UIStroke") then
			button.Cost.UIStroke.Transparency = 0
		end
		if button.Luck:FindFirstChild("UIStroke") then
			button.Luck.UIStroke.Transparency = 0
		end

		button.Activated:Connect(function()
			GUIControls:SuppressRollClickForInputFrame()
			GUIControls:SelectRollType(rollType.id)
		end)
	end
end

function GUIControls:PrepareTutorialTarget(targetId)
	if targetId ~= "roll2Selection" then
		return false
	end
	if GUIControls.CurrentlyRolling == true then
		return false
	end

	local resultPresentationVisible = Main.Visible == true
		or Main.SubInfo.Visible == true
		or Main.SkipButton.Visible == true
		or Main.EquipButton.Visible == true
		or MainButtons.RollButton.Visible ~= true

	if resultPresentationVisible then
		GUIControls.CurrentRollResult = nil
		GUIControls.CurrentRollResultEquipped = false
		GUIControls.EquipDebounce = false
		GUIControls.EquipStatusToken += 1
		restoreIdleRollUi()
		GUIControls:RefreshEquipButton()
		GUIControls:RefreshRollControls()
		GUIControls:SetButtonCooldown()
	end

	return true
end

function GUIControls:IsRollPresentationPending()
	return GUIControls.RollPresentationPending == true
end

function GUIControls:GetTutorialTarget(targetId)
	if targetId == "rollButton" then
		return RollButton
	end
	if targetId == "rollResultSkipButton" then
		if Main.Visible == true and Main.SkipButton.Visible == true then
			return Main.SkipButton
		end
		return nil
	end
	if targetId == "rollDropdownButton" then
		return DropdownButton
	end
	if targetId == "roll2Entry" then
		if RollDropdown.Visible ~= true then
			return nil
		end

		local entry = RollDropdownScrollingFrame:FindFirstChild("roll_2")
		local button = entry and entry:FindFirstChild("Button")
		return if button and button:IsA("GuiObject") then button else nil
	end

	return nil
end

function GUIControls:RollSequence(previewSequence, previewCount)
	Main.SubInfo.Visible = false
	Main.DisplayFrame.Position = BasePosition
	Main.DisplayFrame.ViewportFrame.Position = UDim2.fromScale(0.5, 0.5)
	Main.EquipButton.Visible = false
	Main.SkipButton.Visible = false
	GUIControls:RefreshEquipButton()
	MainButtons.RollButton.Visible = false
	MainButtons.QuickRoll.Visible = false
	MainButtons.AutoRoll.Visible = false
	AutoEquipBestButton.Visible = false
	ShowBlackTween:Play()
	BlurTween:Play()

	local rolls = math.clamp(math.floor(tonumber(previewCount) or #previewSequence), 0, #previewSequence)
	if rolls <= 0 then
		return nil
	end

	local totalTime = GUIControls:GetRollSequenceDuration()
	local offset = 2
	local power = 1.8
	local weights = {}
	local weightSum = 0

	for index = 1, rolls do
		local weight = (index + offset) ^ power
		weights[index] = weight
		weightSum += weight
	end

	for index = 1, rolls do
		local rollInfo = previewSequence[index]
		local duration = (weights[index] / weightSum) * totalTime
		local tween = TweenService:Create(
			DisplayFrame,
			TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = OffsetPosition }
		)
		DisplayFrame.Position = BasePosition
		renderRollInfo(rollInfo, GUIControls.ActiveRollPreviewSessionId)
		SoundUtil.Play(ROLL_TICK_SOUND_NAME)
		tween:Play()
		tween.Completed:Wait()
		if index == rolls then
			return rollInfo
		end
	end
end

function GUIControls:ShowRollResults(rollInfo)
	local resolvedRollInfo = buildResolvedRollResultAudioInfo(rollInfo)

	ShowBlackTween:Play()
	BlurTween:Play()

	local rarityLabel = Main.SubInfo:FindFirstChild("Rarity")
	local sizeLabel = Main.SubInfo:FindFirstChild("Size")
	local mutationLabel = Main.SubInfo:FindFirstChild("Mutation")
	local everRolledLabel = Main.SubInfo:FindFirstChild("EverRolled")
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		local setConfig = if typeof(resolvedRollInfo.PieceId) == "string" and resolvedRollInfo.PieceId ~= ""
			then BodyPartsCatalog.GetSetForPiece(resolvedRollInfo.PieceId)
			else nil
		restoreTextLabelVisualState(rarityLabel, DEFAULT_SUBINFO_RARITY_VISUAL_STATE)
		rarityLabel.Text =
			BodyPartPresentation.FormatTemplatedLabelText(DEFAULT_SUBINFO_RARITY_TEXT, resolvedRollInfo.Rarity or "-")
		BodyPartPresentation.ApplySetRarityTemplateToLabel(
			rarityLabel,
			setConfig,
			resolvedRollInfo.Rarity,
			if typeof(resolvedRollInfo.Color) == "Color3" then resolvedRollInfo.Color else nil
		)
	end
	if mutationLabel and mutationLabel:IsA("TextLabel") then
		restoreTextLabelVisualState(mutationLabel, DEFAULT_SUBINFO_MUTATION_VISUAL_STATE)
		mutationLabel.RichText = true
		mutationLabel.Text = BodyPartPresentation.FormatMutationLabelText(
			DEFAULT_SUBINFO_MUTATION_TEXT,
			{ mutationId = resolveRollResultMutationId(resolvedRollInfo) }
		)
	end

	for _, textObject in Main.SubInfo:GetChildren() do
		if textObject:IsA("TextLabel") then
			textObject.TextTransparency = 1
			if textObject:FindFirstChild("UIStroke") then
				textObject.UIStroke.Transparency = 1
				TweenService:Create(textObject.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Transparency = 0 }):Play()
			end
			TweenService:Create(textObject, TweenInfo.new(0.5, Enum.EasingStyle.Back), { TextTransparency = 0 }):Play()
		end
	end

	Main.SkipButton.Visible = true
	Main.SubInfo.Visible = true
	Main.SubInfo.Size = UDim2.fromScale(0.9, 0.9)
	Main.SubInfo.Position = UDim2.fromScale(0.5, 0.7)

	SubInfoTween:Play()
	Main.DisplayFrame.ViewportFrame.Position = UDim2.fromScale(0.5, 0.5)
	DisplayTween:Play()
	DisplayViewportTween:Play()

	Main.SubInfo.Income.Text = formatRollIncomePerSecond(resolvedRollInfo.CashPerSec)
	Main.SubInfo.BodyPart.Text = resolvedRollInfo.BodyPart
	if sizeLabel and sizeLabel:IsA("TextLabel") then
		local sizeMultiplier = tonumber(resolvedRollInfo.SizeMultiplier)
			or tonumber(GUIControls.CurrentRollResult and GUIControls.CurrentRollResult.sizeResult and GUIControls.CurrentRollResult.sizeResult.scale)
			or tonumber(GUIControls.CurrentRollResult and GUIControls.CurrentRollResult.ownedRecord and GUIControls.CurrentRollResult.ownedRecord.sizeMultiplier)
			or 1
		local sizeName = resolvedRollInfo.Size
			or (GUIControls.CurrentRollResult and GUIControls.CurrentRollResult.sizeResult and GUIControls.CurrentRollResult.sizeResult.displayName)
			or "Normal"
		sizeLabel.Text = formatSizeLabel(sizeName, sizeMultiplier)
		sizeLabel.Visible = true
	end
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Visible = true
	end
	if mutationLabel and mutationLabel:IsA("TextLabel") then
		mutationLabel.Visible = true
	end
	if everRolledLabel and everRolledLabel:IsA("TextLabel") then
		local ownedRecord = GUIControls.CurrentRollResult and GUIControls.CurrentRollResult.ownedRecord
		everRolledLabel.Text = formatRollResultEverRolledText(ownedRecord and ownedRecord.serialNumber)
		everRolledLabel.Visible = true
	end

	renderRollInfo(resolvedRollInfo, GUIControls.ActiveRollPreviewSessionId)
	GUIControls.RollPresentationPending = false
	GUIControls:RefreshEquipButton()
	endRollNotificationHold()
	syncRollResultScreenEffect(resolvedRollInfo)
	stopActiveMutationLoop()
	RollResultAudio.PlayRarity(resolvedRollInfo)
	GUIControls.ActiveMutationLoopSound = RollResultAudio.StartMutationLoop(resolvedRollInfo)

	if GUIControls.AutoRoll then
		local loopId = GUIControls.AutoRollLoopId
		task.delay(GUIControls:GetAutoResultHoldDuration(), function()
			if GUIControls.AutoRoll and loopId == GUIControls.AutoRollLoopId then
				GUIControls:HideRollResults()
			end
		end)
	end
end

function GUIControls:HideRollResults()
	GUIControls.CurrentRollResult = nil
	GUIControls.CurrentRollResultEquipped = false
	GUIControls.EquipDebounce = false
	GUIControls.EquipStatusToken += 1
	GUIControls.RollPresentationPending = false
	restoreIdleRollUi()
	GUIControls:RefreshEquipButton()
	GUIControls:RefreshRollControls()
	GUIControls:SetButtonCooldown()
	if GUIControls.AutoRoll then
		GUIControls:ScheduleNextAutoRoll(GUIControls:GetRollCooldownDuration())
	end
end

local function revealFinalRollResult(rollResult, finalResult)
	if typeof(finalResult) ~= "table" then
		return false
	end

	if shouldPlayRollCutscene(rollResult) then
		playRollCutsceneIfNeeded(rollResult, finalResult, function()
			GUIControls:ShowRollResults(finalResult)
		end)
	else
		GUIControls:ShowRollResults(finalResult)
	end

	return true
end

function GUIControls:Roll(triggerSource)
	task.spawn(function()
		local resolvedTriggerSource = if typeof(triggerSource) == "string" and triggerSource ~= "" then triggerSource else "manual"
		local predictedSkippedPresentation = shouldPredictSkippedRollPresentation(resolvedTriggerSource)

		if os.clock() < GUIControls.SuppressRollClickUntil then
			if resolvedTriggerSource == "auto" then
				GUIControls:ScheduleNextAutoRoll(GUIControls:GetAutoRollRetryDelay())
			end
			return
		end
		if GUIControls.RollDebounce or GUIControls.CurrentlyRolling then
			if resolvedTriggerSource == "auto" then
				GUIControls:ScheduleNextAutoRoll(GUIControls:GetAutoRollRetryDelay())
			end
			return
		end

		GUIControls.CurrentRollResult = nil
		GUIControls.CurrentRollResultEquipped = false
		GUIControls.EquipDebounce = false
		GUIControls.EquipStatusToken += 1
		GUIControls.RollPresentationPending = true
		if not predictedSkippedPresentation then
			stopActiveMutationLoop()
			ScreenEffects.HideAll()
			clearViewport()
			GUIControls.ActiveRollPreviewSessionId = nil
		end
		if resolvedTriggerSource ~= "auto" then
			GUIControls:SetDropdownOpen(false)
		end
		beginRollNotificationHold()
		local rollResponse = invokeRemote(PerformRollRemote, {
			triggerSource = resolvedTriggerSource,
		})
		if not rollResponse then
			GUIControls.RollPresentationPending = false
			endRollNotificationHold()
			GUIControls:SetTemporaryStatus("Failed to reach the server.")
			return
		end

		if not rollResponse.ok or typeof(rollResponse.rollResult) ~= "table" then
			GUIControls.RollPresentationPending = false
			endRollNotificationHold()
			local failureMessage = rollResponse.message or "Roll failed."
			if typeof(rollResponse.state) == "table" then
				GUIControls:ApplyRollingState(rollResponse.state)
			end
			if isInsufficientFundsMessage(failureMessage) then
				if GUIControls.AutoRoll then
					GUIControls:SetAutoRollEnabled(false)
				end
				RollWarningNotifier.ShowInsufficientFundsWarning()
			elseif isInventoryFullMessage(failureMessage) then
				if GUIControls.AutoRoll then
					GUIControls:SetAutoRollEnabled(false)
				end
				Notify.Show(failureMessage, {
					channel = "inventory",
					duration = 4,
				})
				GUIControls:SetTemporaryStatus(failureMessage)
			else
				GUIControls:SetTemporaryStatus(failureMessage)
			end
			return
		end

		GUIControls:ApplyRollingState(rollResponse.state)
		local rollResult = rollResponse.rollResult
		showAutoCraftNotification(rollResult)
		playRollStartSound()
		if rollResult.skipPresentation == true then
			local finalResult = if typeof(rollResult.finalResult) == "table" then rollResult.finalResult else nil
			GUIControls.CurrentRollResult = rollResult
			GUIControls.CurrentRollResultEquipped = rollResult.autoEquipped == true
			GUIControls.EquipDebounce = false
			GUIControls.CurrentlyRolling = false
			if finalResult and shouldPlayRollCutscene(rollResult) then
				Main.Visible = true
				MainButtons.RollButton.Visible = false
				MainButtons.QuickRoll.Visible = false
				MainButtons.AutoRoll.Visible = false
				AutoEquipBestButton.Visible = false
				GUIControls:BeginRollPreviewSession()
				revealFinalRollResult(rollResult, finalResult)
				return
			end

			GUIControls.CurrentRollResult = nil
			GUIControls.CurrentRollResultEquipped = false
			GUIControls.RollPresentationPending = false
			if predictedSkippedPresentation then
				Main.Visible = false
				Main.SkipButton.Visible = false
				Main.SubInfo.Visible = false
				Main.EquipButton.Visible = false
				MainButtons.RollButton.Visible = true
				MainButtons.QuickRoll.Visible = true
				MainButtons.AutoRoll.Visible = true
				AutoEquipBestButton.Visible = true
				GUIControls.ActiveRollPreviewSessionId = nil
			else
				restoreIdleRollUi()
			end
			GUIControls:RefreshEquipButton()
			GUIControls:RefreshRollControls()
			GUIControls:SetButtonCooldown()
			if GUIControls.AutoRoll then
				GUIControls:ScheduleNextAutoRoll(GUIControls:GetRollCooldownDuration())
			end
			GUIControls:SetTemporaryStatus(rollResponse.message or "Roll complete.")
			endRollNotificationHold()
			return
		end

		GUIControls.CurrentlyRolling = true
		Main.Visible = true
		MainButtons.RollButton.Visible = false
		MainButtons.QuickRoll.Visible = false
		MainButtons.AutoRoll.Visible = false
		AutoEquipBestButton.Visible = false

		GUIControls.CurrentRollResult = rollResult
		GUIControls.CurrentRollResultEquipped = rollResult.autoEquipped == true
		GUIControls.EquipDebounce = false

		GUIControls:BeginRollPreviewSession()
		if rollResult.skipPreview == true then
			local finalResult = if typeof(rollResult.finalResult) == "table" then rollResult.finalResult else nil
			GUIControls.CurrentlyRolling = false
			if not revealFinalRollResult(rollResult, finalResult) then
				restoreIdleRollUi()
				GUIControls.RollPresentationPending = false
				endRollNotificationHold()
				GUIControls:RefreshEquipButton()
				GUIControls:RefreshRollControls()
				GUIControls:SetButtonCooldown()
				GUIControls:SetTemporaryStatus(rollResponse.message or "Roll complete.")
			end
			return
		end

		local previewSequence = rollResult.previewSequence
		if typeof(previewSequence) ~= "table" or #previewSequence == 0 then
			previewSequence = buildClientPreviewSequence(rollResult) or { rollResult.finalResult }
		end
		local previewedResult = GUIControls:RollSequence(previewSequence, #previewSequence)
		local finalPreviewEntry = previewSequence[#previewSequence]
		local finalResult = if typeof(finalPreviewEntry) == "table" then finalPreviewEntry else rollResult.finalResult
		GUIControls.CurrentlyRolling = false
		finalResult = if typeof(previewedResult) == "table" then previewedResult else finalResult
		if not revealFinalRollResult(rollResult, finalResult) then
			restoreIdleRollUi()
			GUIControls.RollPresentationPending = false
			endRollNotificationHold()
			GUIControls:RefreshEquipButton()
			GUIControls:RefreshRollControls()
			GUIControls:SetButtonCooldown()
			GUIControls:SetTemporaryStatus(rollResponse.message or "Roll complete.")
		end
	end)
end

function GUIControls:ToggleDropdown()
	GUIControls:SuppressRollClickForInputFrame()
	GUIControls.DropdownInteractionId += 1
	GUIControls:SetDropdownOpen(not GUIControls.IsDropdownOpen)
end

function GUIControls:LoadRollingState()
	GUIControls.RollingStateRefreshPending = false
	local result = invokeRemote(GetRollingStateRemote)
	if not result then
		GUIControls:SetTemporaryStatus("Waiting for rolling state...")
		return false
	end
	if not result.ok then
		GUIControls:SetTemporaryStatus(result.message or "Failed to load rolling state.")
		return false
	end

	GUIControls:SetDropdownOpen(false)
	GUIControls:ApplyRollingState(result.state)
	return true
end

RollButton.Activated:Connect(function()
	GUIControls:Roll()
end)

Main.SkipButton.Activated:Connect(function()
	GUIControls:HideRollResults()
end)

Main.EquipButton.Activated:Connect(function()
	GUIControls:EquipCurrentRollResult()
end)

DropdownButton.Activated:Connect(function()
	GUIControls:SuppressRollClickForInputFrame()
	GUIControls:ToggleDropdown()
end)

LeftButton.Activated:Connect(function()
	GUIControls:SuppressRollClickForInputFrame()
	GUIControls:CycleRollRegion(-1)
end)

RightButton.Activated:Connect(function()
	GUIControls:SuppressRollClickForInputFrame()
	GUIControls:CycleRollRegion(1)
end)

QuickRollButton.Activated:Connect(function()
	GUIControls:ToggleQuickRoll()
end)

AutoEquipBestButton.Activated:Connect(function()
	GUIControls:ToggleAutoEquipBest()
end)

AutoRollButton.Activated:Connect(function()
	GUIControls:ToggleAutoRoll()
end)

ToggleSoundUtil.MarkToggleButton(QuickRollButton)
ToggleSoundUtil.MarkToggleButton(AutoEquipBestButton)
ToggleSoundUtil.MarkToggleButton(AutoRollButton)

RollingUpdatedRemote.OnClientEvent:Connect(function(state)
	GUIControls:ApplyRollingState(state)
end)

RollDropdownInner.Position = DropdownClosedPosition
GUIControls:SetDropdownOpen(false)
RollDropdownTemplate.Visible = false
GUIControls:RefreshRollControls()
task.defer(function()
	local ok, err = pcall(function()
		GUIControls:LoadRollingState()
	end)
	if not ok then
		Logger.Warn(string.format("[RollGUI] Initial rolling state load failed: %s", tostring(err)))
	end
end)

return GUIControls
