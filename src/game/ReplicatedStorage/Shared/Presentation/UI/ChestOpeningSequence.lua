local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local DailyChestConfig = require(ReplicatedStorage.Shared.Config.DailyChestConfig)
local Logger = require(ReplicatedStorage.Shared.Diagnostics.Logger)
local MaterialPresentation = require(ReplicatedStorage.Shared.UI.MaterialPresentation)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local PotionPresentation = require(ReplicatedStorage.Shared.UI.PotionPresentation)
local RollingConfig = require(ReplicatedStorage.Shared.Config.RollingConfig)
local TutorialOverlayGate = require(ReplicatedStorage.Shared.UI.TutorialOverlayGate)

local LOCAL_PLAYER = Players.LocalPlayer
local OVERLAY_NAME = "ChestRewardOverlay"
local CHEST_OFFSET = 2
local CHEST_BASE_ROTATION = CFrame.Angles(0, math.rad(180), 0)
local SCALE_OVERSHOOT = 1.4
local SPIN_DURATION = 0.5
local END_CARD_SIZE = UDim2.fromScale(0.13, 1)
local CENTER_CARD_SIZE = UDim2.fromScale(0.127, 0.243)
local MONEY_DISPLAY_COLOR = Color3.fromRGB(255, 200, 0)
local MONEY_ICON_TEXT = "$"
local TIME_SHARD_DISPLAY_COLOR = Color3.fromRGB(85, 218, 255)
local UNKNOWN_BODY_PART_ODDS_DENOMINATOR = math.huge

local ChestOpeningSequence = {
	_active = false,
	_tutorialTarget = nil :: GuiObject?,
	_tutorialText = nil :: string?,
}

local RARITY_RANKS: { [string]: number } = {}
for rank, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
	RARITY_RANKS[rarity] = rank
end

local function setTutorialTarget(target: GuiObject?, text: string?)
	ChestOpeningSequence._tutorialTarget = target
	ChestOpeningSequence._tutorialText = text
end

local PRESETS = {
	Basic = {
		type = "Normal",
		getColor = function()
			return Color3.new(1, 1, 1)
		end,
	},
	VIP = {
		type = "Normal",
		getColor = function(t)
			local hue = (math.sin(t * 1.5) + 1) / 2
			return Color3.fromHSV(0.08 + hue * 0.08, 1, 1)
		end,
	},
	["VIP+"] = {
		type = "Cycle",
		colors = {
			Color3.fromRGB(140, 0, 255),
			Color3.fromRGB(0, 120, 255),
			Color3.fromRGB(180, 0, 255),
			Color3.fromRGB(0, 200, 255),
		},
	},
	BossTier1 = {
		type = "Cycle",
		colors = {
			Color3.fromRGB(255, 197, 183),
			Color3.fromRGB(255, 229, 164),
		},
	},
	BossTier2 = {
		type = "Cycle",
		colors = {
			Color3.fromRGB(255, 140, 0),
			Color3.fromRGB(255, 152, 148),
		},
	},
	BossTier3 = {
		type = "Cycle",
		colors = {
			Color3.fromRGB(255, 0, 0),
			Color3.fromRGB(255, 153, 153),
		},
	},
}

local function tween(obj: Instance, info: TweenInfo, props: any): Tween?
	if not (obj and obj.Parent) then
		return nil
	end

	local createdTween = TweenService:Create(obj, info, props)
	createdTween:Play()
	return createdTween
end

local function getCamera(): Camera
	local camera = workspace.CurrentCamera
	while not camera do
		workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
		camera = workspace.CurrentCamera
	end
	return camera
end

local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function easeInBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return c3 * t ^ 3 - c1 * t ^ 2
end

local function backPulse(alpha: number): number
	if alpha < 0.5 then
		return 1 + (SCALE_OVERSHOOT - 1) * easeOutBack(alpha / 0.5)
	end

	return SCALE_OVERSHOOT - (SCALE_OVERSHOOT - 1) * easeInBack((alpha - 0.5) / 0.5)
end

local function getCyclingColor(colors: { Color3 }, t: number): Color3
	local count = #colors
	local speed = 1.5
	local index = (t * speed) % count
	local i1 = math.floor(index) + 1
	local i2 = (i1 % count) + 1
	local alpha = index - math.floor(index)

	return colors[i1]:Lerp(colors[i2], alpha)
end

local function getSurfaces(model: Model): { SurfaceAppearance }
	local surfaces = {}
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("SurfaceAppearance") then
			table.insert(surfaces, obj)
		end
	end
	return surfaces
end

local function emit(attachment: Instance?)
	if not attachment then
		return
	end

	for _, descendant in ipairs(attachment:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local count = descendant:GetAttribute("EmitCount")
			if count then
				descendant:Emit(count)
			end
		end
	end
end

local function disableParticles(root: Instance?)
	if not root then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end
end

local function initCameraEffects(): () -> ()
	local dof = Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0
	dof.FocusDistance = 0
	dof.InFocusRadius = 0
	dof.NearIntensity = 0
	dof.Parent = Lighting

	tween(dof, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FarIntensity = 1,
		FocusDistance = 0,
		InFocusRadius = 1,
		NearIntensity = 1,
	})

	return function()
		local outTween = tween(dof, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			FarIntensity = 0,
			InFocusRadius = 0,
			NearIntensity = 0,
		})
		if outTween then
			outTween.Completed:Once(function()
				if dof and dof.Parent then
					dof:Destroy()
				end
			end)
		elseif dof and dof.Parent then
			dof:Destroy()
		end
	end
end

local function createBurstAnchor(camera: Camera, burst: Attachment?): (Part?, RBXScriptConnection?)
	if not burst then
		return nil, nil
	end

	local anchor = Instance.new("Part")
	anchor.Name = "BurstAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Anchored = true
	anchor.CastShadow = false
	anchor.Parent = workspace

	burst.Parent = anchor

	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not (anchor and anchor.Parent) then
			if connection then
				connection:Disconnect()
			end
			return
		end

		anchor.CFrame = camera.CFrame * CFrame.new(0, 0, -CHEST_OFFSET)
	end)

	return anchor, connection
end

local function attachToCamera(camera: Camera, model: Model, state: any): RBXScriptConnection
	local top = model:FindFirstChild("Top", true)
	if top and top:IsA("BasePart") then
		state.top = top
		state.topLocalOffset = model:GetPivot():ToObjectSpace(top.CFrame)
	end

	return RunService.RenderStepped:Connect(function()
		if not (model and model.Parent) then
			return
		end

		local base = camera.CFrame * CFrame.new(0, 0, -CHEST_OFFSET) * CHEST_BASE_ROTATION
		local finalCF = base * (state.spin or CFrame.new())
		model:PivotTo(finalCF)

		local stateTop = state.top
		if stateTop and stateTop.Parent and state.topLocalOffset then
			stateTop.CFrame = finalCF * state.topLocalOffset * (state.lidOffset or CFrame.new())
		end
	end)
end

local function resolveOverlay()
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local overlay = playerGui:WaitForChild(OVERLAY_NAME, 10)
	if not (overlay and overlay:IsA("ScreenGui")) then
		return nil, "PlayerGui.ChestRewardOverlay is missing."
	end

	local itemHolder = overlay:WaitForChild("ItemHolder", 10)
	local confirmButton = overlay:WaitForChild("ConfirmButton", 10)
	local prompt = overlay:WaitForChild("Prompt", 10)
	if not (itemHolder and itemHolder:IsA("Frame")) then
		return nil, "ChestRewardOverlay.ItemHolder is missing."
	end
	if not (confirmButton and confirmButton:IsA("GuiButton")) then
		return nil, "ChestRewardOverlay.ConfirmButton is missing."
	end
	if not (prompt and prompt:IsA("TextLabel")) then
		return nil, "ChestRewardOverlay.Prompt is missing."
	end

	return {
		overlay = overlay,
		itemHolder = itemHolder,
		confirmButton = confirmButton,
		prompt = prompt,
	}, nil
end

local function getInventoryTemplate(): Frame?
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local modalRoot = playerGui:FindFirstChild("ModalRoot")
	local inventory = modalRoot and modalRoot:FindFirstChild("Inventory")
	local scrollingFrame = inventory and inventory:FindFirstChild("ScrollingFrame")
	local template = scrollingFrame and scrollingFrame:FindFirstChild("Template")
	if template and template:IsA("Frame") then
		return template
	end

	return nil
end

local function getCardSurface(frame: Frame): Instance
	local base = frame:FindFirstChild("Base")
	return base or frame
end

local function escapeRichText(text: any): string
	return tostring(text)
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
		:gsub('"', "&quot;")
		:gsub("'", "&apos;")
end

local function toRichTextColor(color: Color3): string
	return string.format(
		"rgb(%d,%d,%d)",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

local function formatWholeNumber(value: any): string
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function formatMoney(value: any): string
	return "$" .. NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function buildCurrencyPresentation(reward: any)
	local kind = tostring(reward and reward.kind or "")
	local amount = math.max(0, math.floor(tonumber(reward and reward.amount) or 0))
	if kind == "timeShard" then
		return {
			cardNameText = string.format(
				'<font color="%s">%s</font>',
				toRichTextColor(TIME_SHARD_DISPLAY_COLOR),
				escapeRichText(reward.displayName or "Time Shards")
			),
			cardUsageText = string.format("x%s", formatWholeNumber(amount)),
			iconTexture = if typeof(reward.iconTexture) == "string" and reward.iconTexture ~= ""
				then reward.iconTexture
				else DailyChestConfig.TimeShardIconTexture,
			cardAccentColor = TIME_SHARD_DISPLAY_COLOR,
			baseFillColor = TIME_SHARD_DISPLAY_COLOR,
			selectedFillColor = TIME_SHARD_DISPLAY_COLOR:Lerp(Color3.new(1, 1, 1), 0.3),
			preferIconOverViewport = true,
		}
	end

	return {
		cardNameText = string.format(
			'<font color="%s">%s</font>',
			toRichTextColor(MONEY_DISPLAY_COLOR),
			escapeRichText(reward.displayName or "Money")
		),
		cardUsageText = if typeof(reward.cardUsageText) == "string" then reward.cardUsageText else formatMoney(amount),
		iconText = MONEY_ICON_TEXT,
		iconTextColor = MONEY_DISPLAY_COLOR,
		cardAccentColor = MONEY_DISPLAY_COLOR,
		baseFillColor = MONEY_DISPLAY_COLOR,
		selectedFillColor = MONEY_DISPLAY_COLOR:Lerp(Color3.new(1, 1, 1), 0.3),
		preferIconOverViewport = true,
	}
end

local function buildRewardPresentation(reward: any)
	local kind = if typeof(reward) == "table" and typeof(reward.kind) == "string" then reward.kind else "bodyPart"
	if kind == "timeShard" or kind == "money" then
		return buildCurrencyPresentation(reward)
	end
	if kind == "material" then
		return MaterialPresentation.BuildPreviewPresentation({
			materialId = reward.materialId,
			record = {
				materialId = reward.materialId,
				amount = reward.amount,
			},
		})
	end
	if kind == "potion" then
		local potionConfig = PotionConfig.Get(reward.potionId)
		local presentation = PotionPresentation.BuildPreviewPresentation({
			potionId = reward.potionId,
			record = {
				potionId = reward.potionId,
				amount = reward.amount,
			},
		})
		if presentation and potionConfig then
			presentation.cardNameText = presentation.cardNameText
				or string.format(
					'<font color="%s">%s</font>',
					toRichTextColor(Color3.fromRGB(205, 160, 255)),
					escapeRichText(potionConfig.label)
				)
			presentation.cardAccentColor = presentation.cardAccentColor or Color3.fromRGB(205, 160, 255)
			presentation.baseFillColor = presentation.baseFillColor or Color3.fromRGB(160, 95, 235)
			presentation.selectedFillColor = presentation.selectedFillColor or Color3.fromRGB(206, 161, 255)
		end
		return presentation
	end

	local record = if typeof(reward) == "table" and typeof(reward.record) == "table" then reward.record else reward
	local presentation = BodyPartPresentation.BuildPreviewPresentation({
		record = record,
		pieceId = record and record.pieceId,
		appearanceUserId = LOCAL_PLAYER.UserId,
	})
	if presentation and typeof(reward) == "table" then
		if reward.autoSold == true then
			presentation.cardUsageText = string.format("Sold %s", formatMoney(reward.payout))
		elseif reward.autoCrafted == true then
			presentation.cardUsageText = "Added to Crafting"
		elseif reward.autoEquipped == true then
			presentation.cardUsageText = "Equipped"
		end
	end
	return presentation
end

local function isBodyPartReward(reward: any): boolean
	if typeof(reward) ~= "table" then
		return false
	end

	local kind = if typeof(reward.kind) == "string" then reward.kind else "bodyPart"
	return kind == "bodyPart"
end

local function getBodyPartRewardRecord(reward: any): any
	if typeof(reward) ~= "table" then
		return nil
	end
	if typeof(reward.record) == "table" then
		return reward.record
	end
	return reward
end

local function getBodyPartRewardSortData(reward: any): (number, number)
	local record = getBodyPartRewardRecord(reward)
	local displayRarity = if typeof(record) == "table" and typeof(record.displayRarity) == "string"
		then record.displayRarity
		elseif typeof(reward) == "table" and typeof(reward.displayRarity) == "string" then reward.displayRarity
		else "Basic"
	local normalizedRarity = RollingConfig.NormalizeDisplayRarity(displayRarity)
	local rarityRank = RARITY_RANKS[normalizedRarity] or math.huge
	local oddsDenominator = UNKNOWN_BODY_PART_ODDS_DENOMINATOR

	if typeof(record) == "table" then
		oddsDenominator = tonumber(record.displayOddsDenominator or record.rarityDenominator) or oddsDenominator
	end
	if oddsDenominator == UNKNOWN_BODY_PART_ODDS_DENOMINATOR and typeof(reward) == "table" then
		oddsDenominator = tonumber(reward.displayOddsDenominator or reward.rarityDenominator) or oddsDenominator
	end

	return rarityRank, math.max(1, oddsDenominator)
end

local function buildOrderedRewardListForReveal(rewards: { any }): { any }
	local orderedRewards = table.create(#rewards)
	local bodyPartEntries = {}

	for index, reward in ipairs(rewards) do
		orderedRewards[index] = reward
		if isBodyPartReward(reward) then
			table.insert(bodyPartEntries, {
				reward = reward,
				originalIndex = index,
			})
		end
	end

	if #bodyPartEntries <= 1 then
		return orderedRewards
	end

	table.sort(bodyPartEntries, function(a, b)
		local rarityRankA, oddsDenominatorA = getBodyPartRewardSortData(a.reward)
		local rarityRankB, oddsDenominatorB = getBodyPartRewardSortData(b.reward)
		if rarityRankA ~= rarityRankB then
			return rarityRankA < rarityRankB
		end
		if oddsDenominatorA ~= oddsDenominatorB then
			return oddsDenominatorA < oddsDenominatorB
		end
		return a.originalIndex < b.originalIndex
	end)

	local nextBodyPartIndex = 1
	for index, reward in ipairs(orderedRewards) do
		if isBodyPartReward(reward) then
			orderedRewards[index] = bodyPartEntries[nextBodyPartIndex].reward
			nextBodyPartIndex += 1
		end
	end

	return orderedRewards
end

local function populateRewardCard(frame: Frame, reward: any)
	local preview = buildRewardPresentation(reward)
	local payload = BodyPartPresentation.BuildBundleCardPayload(preview, {
		isSelected = false,
	})
	if payload then
		BodyPartPresentation.PopulateBundleCard(getCardSurface(frame), payload)
	end
end

local function createCenterItem(screenGui: ScreenGui, reward: any): Frame?
	local template = getInventoryTemplate()
	if not template then
		Logger.Warn("[ChestOpeningSequence] Inventory card template is missing.")
		return nil
	end

	local frame = template:Clone()
	frame.Name = "ChestRewardCard"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0, 0)
	frame.BackgroundTransparency = 1
	frame.Visible = true
	frame.Parent = screenGui
	frame:SetAttribute("GeneratedChestReward", true)

	populateRewardCard(frame, reward)
	tween(frame, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = CENTER_CARD_SIZE,
	})

	return frame
end

local function getItemCount(itemHolder: Frame): number
	local count = 0
	for _, child in ipairs(itemHolder:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "Temp" then
			count += 1
		end
	end
	return count
end

local function getSlotPosition(itemHolder: Frame, layoutBaseSize: UDim2): UDim2
	local list = itemHolder:FindFirstChildOfClass("UIListLayout")
	local padding = (list and list.Padding.Scale) or 0
	local totalItems = getItemCount(itemHolder)
	local itemWidth = END_CARD_SIZE.X.Scale * layoutBaseSize.X.Scale
	local itemSpacing = itemWidth + (padding * itemHolder.Size.X.Scale) * 2
	local totalWidth = itemSpacing * totalItems
	local startX = 0.5 - (totalWidth / 2)
	local x = startX + (itemSpacing * totalItems)

	return UDim2.new(x, 0, itemHolder.Position.Y.Scale, 0)
end

local function getFinalSize(itemHolder: Frame): UDim2
	return UDim2.new(itemHolder.Size.X.Scale * 0.13, 0, itemHolder.Size.Y.Scale, 0)
end

local function animateToSlot(frame: Frame, itemHolder: Frame, layoutBaseSize: UDim2, index: number)
	local found = itemHolder:FindFirstChild("Temp")
	if found then
		found:Destroy()
	end

	local tempFrame = Instance.new("Frame")
	tempFrame.Name = "Temp"
	tempFrame.BackgroundTransparency = 1
	tempFrame.Size = UDim2.fromScale(0, 0)
	tempFrame.Parent = itemHolder

	local finalSize = getFinalSize(itemHolder)
	local finalPos = getSlotPosition(itemHolder, layoutBaseSize)
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	if index > 1 then
		tween(tempFrame, info, { Size = END_CARD_SIZE })
	end

	local moveTween = tween(frame, info, {
		Size = finalSize,
		Position = finalPos,
	})
	if moveTween then
		moveTween.Completed:Wait()
	end

	tempFrame:Destroy()
	frame.Parent = itemHolder
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.Size = END_CARD_SIZE
end

local function playLocalSound(soundTemplate: Sound?): Sound?
	if not soundTemplate then
		return nil
	end

	local sound = soundTemplate:Clone()
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	sound.Ended:Once(function()
		if sound and sound.Parent then
			sound:Destroy()
		end
	end)
	return sound
end

local function spinChest(
	model: Model,
	surfaces: { SurfaceAppearance },
	chestId: string,
	state: any,
	clickIndex: number,
	maxClicks: number,
	burst: Attachment?,
	spinTemplate: Sound?
)
	local preset = PRESETS[chestId] or PRESETS.Basic
	if spinTemplate then
		local pitch = spinTemplate:FindFirstChildOfClass("PitchShiftSoundEffect")
		if pitch then
			pitch.Octave += 0.05
		end
		spinTemplate.PlaybackSpeed = 1 + math.random(-1, 1) / 10
		playLocalSound(spinTemplate)
	end
	emit(burst)

	state.spinId = (state.spinId or 0) + 1
	local spinId = state.spinId
	local startTime = os.clock()
	local maxStrength = math.clamp((clickIndex / maxClicks) * 100, 10, 100)

	task.spawn(function()
		while true do
			if state.spinId ~= spinId then
				return
			end

			local t = os.clock() - startTime
			local alpha = math.clamp(t / SPIN_DURATION, 0, 1)

			state.spin = CFrame.Angles(0, math.rad(360) * alpha, 0)
			model:ScaleTo(backPulse(alpha))

			local strengthAlpha = if alpha < 0.5 then alpha / 0.5 else 1 - ((alpha - 0.5) / 0.5)
			local strength
			local color
			if preset.type == "Cycle" then
				strength = 5 + (95 * strengthAlpha)
				color = getCyclingColor(preset.colors, t)
			else
				strength = maxStrength * strengthAlpha
				color = preset.getColor(t)
			end

			for _, surface in ipairs(surfaces) do
				surface.EmissiveTint = color
				surface.EmissiveStrength = strength
			end

			if alpha >= 1 then
				state.spin = CFrame.new()
				model:ScaleTo(1)
				for _, surface in ipairs(surfaces) do
					surface.EmissiveStrength = if preset.type == "Cycle" then 5 else 0
				end
				return
			end

			RunService.RenderStepped:Wait()
		end
	end)
end

local function openChest(state: any, openTemplate: Sound?): RBXScriptConnection
	playLocalSound(openTemplate)
	local duration = 0.6
	local startTime = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)

		state.lidOffset = CFrame.Angles(math.rad(150 * alpha), 0, 0) * CFrame.new(0, 0.7 * alpha, -0.2 * alpha)

		if alpha >= 1 and connection then
			connection:Disconnect()
		end
	end)
	return connection
end

local function cleanupRewardCards(itemHolder: Frame)
	for _, child in ipairs(itemHolder:GetChildren()) do
		if child:IsA("Frame") and (child:GetAttribute("GeneratedChestReward") == true or child.Name == "ChestRewardCard" or child.Name == "Temp") then
			child:Destroy()
		end
	end
end

local function openChestSequence(chestId: string, rewards: { any }, completedEvent: BindableEvent?): boolean
	if ChestOpeningSequence._active == true then
		Logger.Warn("[ChestOpeningSequence] A chest opening is already active.")
		return false
	end

	local overlayParts, overlayError = resolveOverlay()
	if not overlayParts then
		Logger.Warn("[ChestOpeningSequence] " .. tostring(overlayError))
		return false
	end

	local chestTemplate = GameAssetResolver.Wait(GameAssetPaths.Models.Chests, 10, chestId)
	if not (chestTemplate and chestTemplate:IsA("Model")) then
		Logger.Warn(string.format("[ChestOpeningSequence] Missing chest model '%s'.", tostring(chestId)))
		return false
	end

	local rewardList = if typeof(rewards) == "table" then buildOrderedRewardListForReveal(rewards) else {}
	if #rewardList == 0 then
		Logger.Warn("[ChestOpeningSequence] No rewards were provided for the chest preview.")
		return false
	end

	local releaseOverlayBlock = TutorialOverlayGate.BeginBlock("chest_opening_sequence")
	ChestOpeningSequence._active = true

	local overlay = overlayParts.overlay :: ScreenGui
	local itemHolder = overlayParts.itemHolder :: Frame
	local confirmButton = overlayParts.confirmButton :: GuiButton
	local prompt = overlayParts.prompt :: TextLabel
	local baseSize = itemHolder.Size
	local basePosition = itemHolder.Position
	local layoutBaseSize = itemHolder.Size
	local camera = getCamera()
	local spinTemplate = GameAssetResolver.Find(GameAssetPaths.Audio.Chests, "Spin")
	local openTemplate = GameAssetResolver.Find(GameAssetPaths.Audio.Chests, "Open")
	local spinSound = if spinTemplate and spinTemplate:IsA("Sound") then spinTemplate:Clone() else nil
	local openSound = if openTemplate and openTemplate:IsA("Sound") then openTemplate :: Sound else nil
	local pitch = spinSound and spinSound:FindFirstChildOfClass("PitchShiftSoundEffect")
	if pitch then
		pitch.Octave = 1
	end

	cleanupRewardCards(itemHolder)
	itemHolder.Size = baseSize
	itemHolder.Position = basePosition
	overlay.Enabled = true
	prompt.Visible = true
	confirmButton.Visible = false
	setTutorialTarget(prompt, "Open your chest.")

	local chest = chestTemplate:Clone()
	chest.Parent = workspace
	chest:ScaleTo(1)

	local surfaces = getSurfaces(chest)
	local state = {
		spin = CFrame.new(),
		lidOffset = nil,
		topLocalOffset = nil,
		spinId = 0,
	}
	local cameraConnection = attachToCamera(camera, chest, state)
	local bottomPart = chest:FindFirstChild("Bottom", true)
	local burstAttachment = bottomPart and bottomPart:FindFirstChild("Burst")
	local burstAnchor, anchorConnection = createBurstAnchor(camera, if burstAttachment and burstAttachment:IsA("Attachment") then burstAttachment else nil)
	local cleanupEffects = initCameraEffects()
	local currentItem: Frame? = nil
	local clicks = 0
	local acceptingInput = true
	local openedConnection: RBXScriptConnection? = nil
	local inputConnection: RBXScriptConnection? = nil
	local confirmConnection: RBXScriptConnection? = nil

	local function finish()
		acceptingInput = false
		if inputConnection then
			inputConnection:Disconnect()
			inputConnection = nil
		end
		if confirmConnection then
			confirmConnection:Disconnect()
			confirmConnection = nil
		end
		if cameraConnection then
			cameraConnection:Disconnect()
		end
		if anchorConnection then
			anchorConnection:Disconnect()
		end
		if openedConnection then
			openedConnection:Disconnect()
		end
		if spinSound then
			spinSound:Destroy()
		end
		if burstAnchor then
			burstAnchor:Destroy()
		end

		cleanupEffects()
		confirmButton.Visible = false
		prompt.Visible = false
		cleanupRewardCards(itemHolder)
		itemHolder.Size = baseSize
		itemHolder.Position = basePosition

		for _, descendant in ipairs(chest:GetDescendants()) do
			if descendant:IsA("BasePart") then
				tween(descendant, TweenInfo.new(0.3), { Transparency = 1 })
			end
		end
		task.delay(0.3, function()
			if chest and chest.Parent then
				chest:Destroy()
			end
			overlay.Enabled = false
			ChestOpeningSequence._active = false
			setTutorialTarget(nil, nil)
			releaseOverlayBlock()
			if completedEvent then
				completedEvent:Fire(true)
			end
		end)
	end

	local function advance()
		if not acceptingInput then
			return
		end

		clicks += 1
		if clicks <= #rewardList then
			setTutorialTarget(prompt, "Open your chest.")
			if currentItem then
				local previousItem = currentItem
				task.spawn(function()
					animateToSlot(previousItem, itemHolder, layoutBaseSize, clicks - 1)
				end)
			end

			currentItem = createCenterItem(overlay, rewardList[clicks])
			spinChest(chest, surfaces, chestId, state, clicks, #rewardList, if burstAttachment and burstAttachment:IsA("Attachment") then burstAttachment else nil, spinSound)
			return
		end

		if clicks == #rewardList + 1 then
			prompt.Visible = false
			disableParticles(chest)
			acceptingInput = false

			if inputConnection then
				inputConnection:Disconnect()
				inputConnection = nil
			end

			if currentItem then
				animateToSlot(currentItem, itemHolder, layoutBaseSize, #rewardList)
			end

			tween(itemHolder, TweenInfo.new(0.4, Enum.EasingStyle.Back), {
				Size = UDim2.new(0.6, 0, 0.4, 0),
				Position = UDim2.new(0.5, 0, 0.5, 0),
			})
			openedConnection = openChest(state, openSound)
			confirmButton.Visible = true
			setTutorialTarget(confirmButton, "Claim your rewards.")
			confirmConnection = confirmButton.Activated:Once(finish)
		end
	end

	inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			advance()
		end
	end)

	return true
end

function ChestOpeningSequence.OpenChest(chestId: string, rewards: { any }): boolean
	return openChestSequence(chestId, rewards, nil)
end

function ChestOpeningSequence.IsActive(): boolean
	return ChestOpeningSequence._active == true
end

function ChestOpeningSequence.GetTutorialTarget(): (GuiObject?, string?)
	local target = ChestOpeningSequence._tutorialTarget
	if ChestOpeningSequence._active ~= true or not (target and target.Parent) then
		return nil, nil
	end

	return target, ChestOpeningSequence._tutorialText
end

function ChestOpeningSequence.OpenChestAsync(chestId: string, rewards: { any }): boolean
	local completedEvent = Instance.new("BindableEvent")
	local started = openChestSequence(chestId, rewards, completedEvent)
	if not started then
		completedEvent:Destroy()
		return false
	end

	local ok = completedEvent.Event:Wait()
	completedEvent:Destroy()
	return ok == true
end

return ChestOpeningSequence
