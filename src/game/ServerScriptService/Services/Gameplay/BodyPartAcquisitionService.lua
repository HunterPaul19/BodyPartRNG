local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Common.Signal)
local BodyPartEconomy = require(ReplicatedStorage.Shared.Character.BodyPartEconomy)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local RollingConfig = require(ReplicatedStorage.Shared.Config.RollingConfig)
local BodyPartService = require(script.Parent.BodyPartService)
local CraftingService = require(script.Parent.CraftingService)
local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)

export type AcquisitionOptions = {
	source: string?,
	presentation: string?,
	reservation: any?,
	ignoreInventoryLimit: boolean?,
	isBossPart: boolean?,
	sourceBossId: string?,
	allowAutoEquip: boolean?,
	allowAutoCraft: boolean?,
	allowAutoSell: boolean?,
}

export type AcquisitionResult = {
	status: string,
	record: any?,
	rewardEntry: any?,
	message: string?,
	error: string?,
	payout: number?,
	reservation: any?,
	reservationConsumed: boolean?,
	autoSellRarity: string?,
	autoCrafted: boolean?,
	autoEquipped: boolean?,
	pendingAutoSell: boolean?,
}

local BodyPartAcquisitionService = {}
BodyPartAcquisitionService.Acquired = Signal.new()

local function cloneTable(value: any): any
	if typeof(value) ~= "table" then
		return nil
	end

	return table.clone(value)
end

local function buildReservation(options: AcquisitionOptions?): any?
	if typeof(options) ~= "table" then
		return nil
	end

	local sourceReservation = if typeof(options.reservation) == "table" then table.clone(options.reservation) else nil
	if sourceReservation == nil then
		if options.ignoreInventoryLimit == true then
			sourceReservation = {
				ignoreInventoryLimit = true,
			}
		end
		return sourceReservation
	end

	if options.ignoreInventoryLimit == true then
		sourceReservation.ignoreInventoryLimit = true
	end

	return sourceReservation
end

local function getPayloadPiece(payload: any): any?
	local pieceId = if typeof(payload) == "table" then payload.pieceId else nil
	if typeof(pieceId) ~= "string" or pieceId == "" then
		return nil
	end

	return BodyPartsCatalog.GetPiece(pieceId)
end

local function getPayloadDisplayName(payload: any, piece: any?): string
	if piece ~= nil and typeof(piece.displayName) == "string" and piece.displayName ~= "" then
		return piece.displayName
	end
	if typeof(payload) == "table" and typeof(payload.rolledSetDisplayName) == "string" and payload.rolledSetDisplayName ~= "" then
		return payload.rolledSetDisplayName
	end
	if typeof(payload) == "table" and typeof(payload.pieceId) == "string" then
		return payload.pieceId
	end

	return "body part"
end

local function buildTransientRecord(payload: any, reservation: any?): any?
	local record = cloneTable(payload)
	if record == nil then
		return nil
	end

	record.ownedId = if typeof(record.ownedId) == "string" then record.ownedId else ""
	record.serialNumber = math.max(0, math.floor(tonumber(record.serialNumber) or tonumber(reservation and reservation.serialNumber) or 0))
	record.isFavorite = record.isFavorite == true
	return record
end

local function buildRewardEntry(
	payload: any,
	record: any?,
	options: AcquisitionOptions?,
	status: string,
	message: string?,
	payout: number?,
	autoSellRarity: string?
): any
	local piece = getPayloadPiece(payload)
	local displayName = getPayloadDisplayName(payload, piece)
	local setId = if typeof(payload) == "table" and typeof(payload.rolledSetId) == "string"
		then payload.rolledSetId
		elseif piece and typeof(piece.setId) == "string" then piece.setId
		else nil
	local displayRarity = if typeof(payload) == "table" and typeof(payload.displayRarity) == "string"
		then payload.displayRarity
		else autoSellRarity or "Basic"
	local displayOddsDenominator = math.max(1, math.floor(
		tonumber(payload and payload.displayOddsDenominator)
			or tonumber(payload and payload.rarityDenominator)
			or 1
	))

	return {
		kind = "bodyPart",
		pieceId = if typeof(payload) == "table" then payload.pieceId else nil,
		displayName = displayName,
		setId = setId,
		displayRarity = displayRarity,
		displayOddsDenominator = displayOddsDenominator,
		isBossPart = typeof(options) == "table" and options.isBossPart == true,
		record = record,
		sourceBossId = if typeof(options) == "table" and typeof(options.sourceBossId) == "string" then options.sourceBossId else nil,
		acquisitionStatus = status,
		autoSold = status == "autoSold",
		autoCrafted = status == "autoCrafted",
		autoEquipped = status == "equipped",
		payout = payout,
		outcomeMessage = message,
	}
end

local function buildFailedResult(message: string?): AcquisitionResult
	return {
		status = "failed",
		error = message or "Failed to grant body part.",
		message = message or "Failed to grant body part.",
		reservationConsumed = false,
	}
end

local function normalizeAutoCraftMessage(message: any, options: AcquisitionOptions?): string
	local text = tostring(message or "Added body part to crafting.")
	if typeof(options) == "table" and options.source ~= "roll" then
		text = string.gsub(text, "Added roll", "Added body part")
	end

	return text
end

local function publishAcquired(player: Player, grantPayload: any, result: AcquisitionResult, options: AcquisitionOptions?): AcquisitionResult
	local rewardEntry = result.rewardEntry
	local displayRarity = if typeof(rewardEntry) == "table"
		then rewardEntry.displayRarity
		elseif typeof(grantPayload) == "table" then grantPayload.displayRarity
		else nil

	BodyPartAcquisitionService.Acquired:Fire({
		player = player,
		status = result.status,
		record = result.record,
		rewardEntry = rewardEntry,
		displayRarity = displayRarity,
		source = if typeof(options) == "table" then options.source else nil,
	})

	return result
end

function BodyPartAcquisitionService:SellTransientBodyPart(player: Player, record: any, options: AcquisitionOptions?): AcquisitionResult
	if typeof(record) ~= "table" then
		return buildFailedResult("No body part was available to sell.")
	end

	local piece = BodyPartsCatalog.GetPiece(record.pieceId)
	local pieceName = getPayloadDisplayName(record, piece)
	local payout = BodyPartEconomy.GetSellValue(record, piece)
	DataService:AddMoney(player, payout, "sell_single")
	StatsService:RecordBodyPartsSold(player, 1)
	StatsService:RecordTransientBodyPartAcquired(player)

	local message = string.format("Sold %s for $%s.", pieceName, tostring(payout))
	local autoSellRarity = RollingConfig.NormalizeDisplayRarity(record.displayRarity)
	return publishAcquired(player, record, {
		status = "autoSold",
		record = record,
		rewardEntry = buildRewardEntry(record, record, options, "autoSold", message, payout, autoSellRarity),
		message = message,
		payout = payout,
		reservation = if typeof(options) == "table" then options.reservation else nil,
		reservationConsumed = true,
		autoSellRarity = autoSellRarity,
		autoCrafted = false,
		autoEquipped = false,
		pendingAutoSell = false,
	}, options)
end

function BodyPartAcquisitionService:Acquire(
	player: Player,
	grantPayload: any,
	options: AcquisitionOptions?
): AcquisitionResult
	if typeof(grantPayload) ~= "table" then
		return buildFailedResult("Body part grant payload must be a table.")
	end

	local acquisitionOptions: AcquisitionOptions = if typeof(options) == "table" then options else {}
	local presentation = if typeof(acquisitionOptions.presentation) == "string" then acquisitionOptions.presentation else "immediate_reward"
	local autoSellRarity = RollingConfig.NormalizeDisplayRarity(grantPayload.displayRarity)
	local allowAutoEquip = acquisitionOptions.allowAutoEquip ~= false
	local allowAutoCraft = acquisitionOptions.allowAutoCraft ~= false
	local allowAutoSell = acquisitionOptions.allowAutoSell ~= false
	local shouldAutoEquip = false

	if allowAutoEquip and DataService:GetAutoEquipBestEnabled(player) then
		shouldAutoEquip = BodyPartService:IsBodyPartGrantBetterThanEquipped(player, grantPayload)
	end

	if shouldAutoEquip then
		local reservation = buildReservation(acquisitionOptions)
		local ownedRecord, grantError = DataService:AddOwnedBodyPart(player, grantPayload, reservation)
		if not ownedRecord then
			return buildFailedResult(grantError or "Failed to save the body part.")
		end

		local equipped, equipMessage = BodyPartService:EquipOwnedBodyPartIfBetter(player, ownedRecord.ownedId, ownedRecord.sizeMultiplier, {
			applyVisuals = true,
		})
		local status = if equipped then "equipped" else "kept"
		local message = equipMessage or (if equipped then "Equipped body part." else "Kept body part.")

		return publishAcquired(player, grantPayload, {
			status = status,
			record = ownedRecord,
			rewardEntry = buildRewardEntry(grantPayload, ownedRecord, acquisitionOptions, status, message, nil, autoSellRarity),
			message = message,
			reservation = reservation,
			reservationConsumed = true,
			autoSellRarity = autoSellRarity,
			autoCrafted = false,
			autoEquipped = equipped == true,
			pendingAutoSell = false,
		}, acquisitionOptions)
	end

	if allowAutoCraft then
		local autoCraftResult = CraftingService:TryAutoCommitRolledBodyPart(player, grantPayload)
		if typeof(autoCraftResult) == "table" and autoCraftResult.committed == true then
			local record = buildTransientRecord(grantPayload, nil)
			local message = normalizeAutoCraftMessage(autoCraftResult.message, acquisitionOptions)
			return publishAcquired(player, grantPayload, {
				status = "autoCrafted",
				record = record,
				rewardEntry = buildRewardEntry(grantPayload, record, acquisitionOptions, "autoCrafted", message, nil, autoSellRarity),
				message = message,
				reservation = if typeof(acquisitionOptions) == "table" then acquisitionOptions.reservation else nil,
				reservationConsumed = false,
				autoSellRarity = autoSellRarity,
				autoCrafted = autoCraftResult.crafted == true,
				autoEquipped = false,
				pendingAutoSell = false,
			}, acquisitionOptions)
		end
	end

	local autoSellEnabled = allowAutoSell and DataService:IsAutoSellEnabledForRarity(player, autoSellRarity)
	if autoSellEnabled then
		local record
		local reservation = buildReservation(acquisitionOptions)
		local grantError

		if typeof(reservation) == "table" and tonumber(reservation.serialNumber) ~= nil then
			record = buildTransientRecord(grantPayload, reservation)
		else
			record, reservation, grantError = DataService:ReserveBodyPartRollRecord(player, grantPayload)
		end
		if not record then
			return buildFailedResult(grantError or "Failed to reserve the body part.")
		end

		if presentation == "roll_pending" then
			local message = string.format("%s roll result is pending auto-sell.", autoSellRarity)
			return publishAcquired(player, grantPayload, {
				status = "pendingAutoSell",
				record = record,
				rewardEntry = buildRewardEntry(grantPayload, record, acquisitionOptions, "pendingAutoSell", message, nil, autoSellRarity),
				message = message,
				reservation = reservation,
				reservationConsumed = true,
				autoSellRarity = autoSellRarity,
				autoCrafted = false,
				autoEquipped = false,
				pendingAutoSell = true,
			}, acquisitionOptions)
		end

		local sellResult = self:SellTransientBodyPart(player, record, acquisitionOptions)
		StatsService:RecordAutoSellOutcome(player, "sold")
		sellResult.reservation = reservation
		sellResult.reservationConsumed = true
		sellResult.autoSellRarity = autoSellRarity
		sellResult.pendingAutoSell = false
		return sellResult
	end

	local reservation = buildReservation(acquisitionOptions)
	local ownedRecord, grantError = DataService:AddOwnedBodyPart(player, grantPayload, reservation)
	if not ownedRecord then
		return buildFailedResult(grantError or "Failed to save the body part.")
	end

	local message = string.format("Kept %s.", getPayloadDisplayName(grantPayload, getPayloadPiece(grantPayload)))
	return publishAcquired(player, grantPayload, {
		status = "kept",
		record = ownedRecord,
		rewardEntry = buildRewardEntry(grantPayload, ownedRecord, acquisitionOptions, "kept", message, nil, autoSellRarity),
		message = message,
		reservation = reservation,
		reservationConsumed = true,
		autoSellRarity = autoSellRarity,
		autoCrafted = false,
		autoEquipped = false,
		pendingAutoSell = false,
	}, acquisitionOptions)
end

return BodyPartAcquisitionService
