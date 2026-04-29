local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local BossRewards = require(ReplicatedStorage.Shared.BossArena.BossRewards)
local BossQueueConstants = require(ReplicatedStorage.Shared.BossQueue.Constants)
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)

local LOCAL_PLAYER = Players.LocalPlayer
local ACTIVE_PROFILE_ID = "boss_lobby"
local BILLBOARD_NAME = "BossBillboard"
local SHOW_RADIUS_STUDS = 67.5
local HIDE_RADIUS_STUDS = 77.5
local HITBOX_HIDE_PADDING_STUDS = 10
local REFRESH_INTERVAL_SECONDS = 0.1

type PortalRecord = {
	instance: Model,
	bossName: string,
	hitbox: BasePart?,
	attachment: Attachment?,
	hitboxRadius: number,
	showRadius: number,
	hideRadius: number,
}

local BossLobbyRewardPreviewController = {
	_started = false,
	_billboard = nil :: BillboardGui?,
	_template = nil :: Frame?,
	_activePortal = nil :: Model?,
	_portalsByInstance = {} :: { [Instance]: PortalRecord },
	_connections = {} :: { RBXScriptConnection },
	_elapsedSinceRefresh = 0,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function normalizeString(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local trimmed = string.match(value, "%S.*")
	return trimmed or ""
end

local function getCharacterRoot(): BasePart?
	local character = LOCAL_PLAYER.Character
	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getPortalHitbox(portal: Model): BasePart?
	local hitbox = portal:FindFirstChild("Hitbox", true)
	return if hitbox and hitbox:IsA("BasePart") then hitbox else nil
end

local function getPortalAttachment(portal: Model): Attachment?
	local teleport = portal:FindFirstChild("Teleport")
	local attachment = if teleport then teleport:FindFirstChild("DisplayAttachment", true) else nil
	return if attachment and attachment:IsA("Attachment") then attachment else nil
end

local function computeRevealRadius(hitbox: BasePart?): number
	if hitbox == nil then
		return 0
	end

	return math.max(hitbox.Size.X, hitbox.Size.Z) * 0.5
end

local function computePortalShowRadius(hitboxRadius: number): number
	return math.max(SHOW_RADIUS_STUDS, hitboxRadius)
end

local function computePortalHideRadius(hitboxRadius: number): number
	return math.max(HIDE_RADIUS_STUDS, hitboxRadius + HITBOX_HIDE_PADDING_STUDS)
end

local function getPortalDistance(record: PortalRecord, root: BasePart): number
	local targetPosition
	if record.hitbox then
		targetPosition = record.hitbox.Position
	elseif record.attachment then
		targetPosition = record.attachment.WorldPosition
	else
		local cframe = record.instance:GetBoundingBox()
		targetPosition = cframe.Position
	end

	return (root.Position - targetPosition).Magnitude
end

local function findTextLabel(root: Instance, name: string): TextLabel?
	local instance = root:FindFirstChild(name, true)
	return if instance and instance:IsA("TextLabel") then instance else nil
end

local function findViewport(root: Instance, name: string): ViewportFrame?
	local instance = root:FindFirstChild(name, true)
	return if instance and instance:IsA("ViewportFrame") then instance else nil
end

local function clearGeneratedRewardRows(scrollingFrame: ScrollingFrame, template: Frame)
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child ~= template and child:GetAttribute("BossRewardPreviewGenerated") == true then
			child:Destroy()
		end
	end
end

local function updateScrollingCanvas(scrollingFrame: ScrollingFrame)
	local layout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if layout == nil then
		return
	end

	scrollingFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
end

function BossLobbyRewardPreviewController:_getBillboard(): BillboardGui?
	if self._billboard and self._billboard.Parent ~= nil then
		return self._billboard
	end

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui", 10)
	if playerGui == nil then
		return nil
	end

	local billboard = playerGui:WaitForChild(BILLBOARD_NAME, 10)
	if not (billboard and billboard:IsA("BillboardGui")) then
		return nil
	end

	billboard.Enabled = false
	billboard.MaxDistance = math.huge
	self._billboard = billboard
	self._template = nil
	return billboard
end

function BossLobbyRewardPreviewController:_getTemplate(scrollingFrame: ScrollingFrame): Frame?
	if self._template and self._template.Parent == scrollingFrame then
		return self._template
	end

	local template = scrollingFrame:FindFirstChild("Template")
	if not (template and template:IsA("Frame")) then
		return nil
	end

	template.Visible = false
	self._template = template
	return template
end

function BossLobbyRewardPreviewController:_renderBossCharacter(billboard: BillboardGui, bossName: string)
	local characterFrame = billboard:FindFirstChild("Character", true)
	local viewport = if characterFrame then characterFrame:FindFirstChild("Character") else nil
	if not (viewport and viewport:IsA("ViewportFrame")) then
		return
	end

	local bossRig = GameAssetResolver.Find(GameAssetPaths.Models.Bosses, bossName)
	local baseRig = BodyPartsCatalog.GetDefaultBaseRig()
	if bossRig and bossRig:IsA("Model") then
		ViewportModelRenderer.RenderCharacterModelAtFramingPivot(viewport, bossRig, baseRig)
	else
		ViewportModelRenderer.Clear(viewport)
	end
end

function BossLobbyRewardPreviewController:_renderRewards(billboard: BillboardGui, bossName: string)
	local scrollingFrame = billboard:FindFirstChild("ScrollingFrame", true)
	if not (scrollingFrame and scrollingFrame:IsA("ScrollingFrame")) then
		return
	end

	local template = self:_getTemplate(scrollingFrame)
	if template == nil then
		return
	end

	template.Visible = false
	clearGeneratedRewardRows(scrollingFrame, template)

	for index, entry in ipairs(BossRewards.GetBossRewardPreviewEntries(bossName)) do
		local row = template:Clone()
		row.Name = string.format("Reward_%03d", index)
		row:SetAttribute("BossRewardPreviewGenerated", true)
		row.LayoutOrder = index
		row.Visible = true
		row.Parent = scrollingFrame

		local itemName = findTextLabel(row, "ItemName")
		if itemName then
			itemName.Text = entry.displayName
		end

		local chanceLabel = findTextLabel(row, "Chance")
		if chanceLabel then
			BodyPartPresentation.ApplySetRarityTemplateToLabel(
				chanceLabel,
				BodyPartsCatalog.GetSet(entry.setId),
				entry.displayRarity
			)
			chanceLabel.Text = NumberFormatter.FormatOneInChance(entry.chance)
		end

		local itemViewport = findViewport(row, "ItemViewport")
		if itemViewport then
			ViewportModelRenderer.RenderBodyPartPreview(itemViewport, entry.bundleModel, nil, nil, nil, nil, nil)
		end
	end

	updateScrollingCanvas(scrollingFrame)
end

function BossLobbyRewardPreviewController:_showPortal(record: PortalRecord)
	local billboard = self:_getBillboard()
	if billboard == nil or record.attachment == nil then
		return
	end

	if self._activePortal ~= record.instance then
		self._activePortal = record.instance
		local header = findTextLabel(billboard, "Header")
		if header then
			header.Text = record.bossName
		end

		self:_renderBossCharacter(billboard, record.bossName)
		self:_renderRewards(billboard, record.bossName)
	end

	billboard.Adornee = record.attachment
	billboard.Enabled = true
end

function BossLobbyRewardPreviewController:_hide()
	local billboard = self:_getBillboard()
	if billboard then
		billboard.Enabled = false
		billboard.Adornee = nil
	end

	self._activePortal = nil
end

function BossLobbyRewardPreviewController:_refreshNearestPortal()
	local root = getCharacterRoot()
	if root == nil then
		self:_hide()
		return
	end

	local nearestRecord = nil
	local nearestDistance = math.huge

	for instance, record in pairs(self._portalsByInstance) do
		if instance.Parent == nil or record.attachment == nil or record.bossName == "" then
			self._portalsByInstance[instance] = nil
			continue
		end

		local distance = getPortalDistance(record, root)
		local isActivePortal = self._activePortal == instance
		local allowedRadius = if isActivePortal then record.hideRadius else record.showRadius
		if distance <= allowedRadius and distance < nearestDistance then
			nearestRecord = record
			nearestDistance = distance
		end
	end

	if nearestRecord then
		self:_showPortal(nearestRecord)
	else
		self:_hide()
	end
end

function BossLobbyRewardPreviewController:_registerPortal(instance: Instance)
	if self._portalsByInstance[instance] ~= nil or not instance:IsA("Model") then
		return
	end

	local bossName = normalizeString(instance:GetAttribute(BossQueueConstants.BossNameAttribute))
	if bossName == "" then
		bossName = normalizeString(instance:GetAttribute("bossName"))
	end

	local hitbox = getPortalHitbox(instance)
	local attachment = getPortalAttachment(instance)
	local hitboxRadius = computeRevealRadius(hitbox)
	self._portalsByInstance[instance] = {
		instance = instance,
		bossName = bossName,
		hitbox = hitbox,
		attachment = attachment,
		hitboxRadius = hitboxRadius,
		showRadius = computePortalShowRadius(hitboxRadius),
		hideRadius = computePortalHideRadius(hitboxRadius),
	}
end

function BossLobbyRewardPreviewController:_unregisterPortal(instance: Instance)
	if self._activePortal == instance then
		self:_hide()
	end

	self._portalsByInstance[instance] = nil
end

function BossLobbyRewardPreviewController:OnStart()
	if self._started then
		return
	end

	self._started = true
	if RunService:IsClient() ~= true or not isEnabledForPlace() then
		return
	end

	self:_getBillboard()

	for _, instance in ipairs(CollectionService:GetTagged(BossQueueConstants.PortalTag)) do
		self:_registerPortal(instance)
	end

	table.insert(self._connections, CollectionService:GetInstanceAddedSignal(BossQueueConstants.PortalTag):Connect(function(instance)
		self:_registerPortal(instance)
	end))
	table.insert(self._connections, CollectionService:GetInstanceRemovedSignal(BossQueueConstants.PortalTag):Connect(function(instance)
		self:_unregisterPortal(instance)
	end))
	table.insert(self._connections, RunService.RenderStepped:Connect(function(deltaTime: number)
		self._elapsedSinceRefresh += deltaTime
		if self._elapsedSinceRefresh < REFRESH_INTERVAL_SECONDS then
			return
		end

		self._elapsedSinceRefresh = 0
		self:_refreshNearestPortal()
	end))
end

return BossLobbyRewardPreviewController
