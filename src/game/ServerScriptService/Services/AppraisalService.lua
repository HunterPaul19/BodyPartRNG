local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local AppraisalPricing = require(ReplicatedStorage.Shared.Character.AppraisalPricing)
local AppraisalState = require(ReplicatedStorage.Shared.Character.AppraisalState)
local BodyPartEconomy = require(ReplicatedStorage.Shared.Character.BodyPartEconomy)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local AppraisalConfig = require(ReplicatedStorage.Shared.Config.AppraisalConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local RollMath = require(ReplicatedStorage.Shared.Rolling.RollMath)
local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)

local REMOTES_FOLDER_NAME = "Remotes"
local APPRAISAL_FOLDER_NAME = "Appraisal"
local GET_STATE_REMOTE_NAME = "GetState"
local PERFORM_APPRAISAL_REMOTE_NAME = "PerformAppraisal"
local UPDATED_REMOTE_NAME = "Updated"
local PARKING_FOLDER_NAME = "AppraisalNpcParking"
local APPRAISER_MODEL_NAME = "Appraiser"

local remotesFolder: Folder? = nil
local appraisalFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local performAppraisalRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil

local AppraisalService = {
	_started = false,
	_state = AppraisalState.CreateEmptyState(),
	_cycleId = -1,
	_stockRemaining = AppraisalConfig.stockPerSpawn,
	_forcedActiveUntil = 0,
	_appraiserModel = nil :: Model?,
	_workspaceParent = nil :: Instance?,
}

local function response(ok: boolean, message: string, appraisalState: any?, appraisalResult: any?, code: string?)
	return {
		ok = ok,
		message = message,
		code = code,
		appraisalState = AppraisalState.CloneState(appraisalState),
		appraisalResult = appraisalResult,
	}
end

local function ensureRemotesFolder(): Folder
	if remotesFolder and remotesFolder.Parent == ReplicatedStorage then
		return remotesFolder
	end

	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
	return folder
end

local function ensureAppraisalFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if appraisalFolder and appraisalFolder.Parent == rootFolder then
		return appraisalFolder
	end

	local existing = rootFolder:FindFirstChild(APPRAISAL_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		appraisalFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = APPRAISAL_FOLDER_NAME
	folder.Parent = rootFolder
	appraisalFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureAppraisalFolder()
	if cachedRemote and cachedRemote.Parent == folder then
		return cachedRemote
	end

	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local function ensureUpdatedRemote(): RemoteEvent
	local folder = ensureAppraisalFolder()
	if updatedRemote and updatedRemote.Parent == folder then
		return updatedRemote
	end

	local existing = folder:FindFirstChild(UPDATED_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		updatedRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = UPDATED_REMOTE_NAME
	remote.Parent = folder
	updatedRemote = remote
	return remote
end

local function ensureParkingFolder(): Folder
	local existing = ServerStorage:FindFirstChild(PARKING_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = PARKING_FOLDER_NAME
	folder.Parent = ServerStorage
	return folder
end

local function chooseWeightedEntry(randomSource: Random, entries: { any })
	return RollMath.ChooseWeighted(randomSource, entries, function(entry)
		return entry.weight
	end)
end

local function buildCycleState(now: number, stockRemaining: number, forcedActiveUntil: number?)
	local cycleInterval = AppraisalConfig.cycleIntervalSeconds
	local activeDuration = AppraisalConfig.activeDurationSeconds
	local cycleId = math.floor(now / cycleInterval)
	local cycleStartsAt = cycleId * cycleInterval
	local departsAt = cycleStartsAt + activeDuration
	local forcedDeparture = math.max(0, math.floor(tonumber(forcedActiveUntil) or 0))
	local isForcedActive = forcedDeparture > now
	local resolvedDepartsAt = if isForcedActive then math.max(departsAt, forcedDeparture) else departsAt

	return {
		cycleId = cycleId,
		isActive = isForcedActive or now < departsAt,
		stockRemaining = math.clamp(math.floor(tonumber(stockRemaining) or 0), 0, AppraisalConfig.stockPerSpawn),
		stockPerSpawn = AppraisalConfig.stockPerSpawn,
		departsAt = resolvedDepartsAt,
		nextAppearsAt = (cycleId + 1) * cycleInterval,
	}
end

local function buildAppraisalSnapshot(record: any, piece: any)
	return {
		mutationId = MutationConfig.NormalizeId(record and record.mutationId),
		mutationDisplayName = MutationConfig.GetDisplayName(record and record.mutationId),
		sizeId = SizeConfig.NormalizeId(record and record.sizeId),
		sizeScale = SizeConfig.NormalizeScale(record and record.sizeMultiplier, record and record.sizeId),
		sellValue = BodyPartEconomy.GetSellValue(record, piece),
	}
end

function AppraisalService:_ensureNpcResolved()
	if self._appraiserModel and self._appraiserModel.Parent then
		return
	end

	local parkingFolder = ensureParkingFolder()
	local workspaceModel = Workspace:FindFirstChild(APPRAISER_MODEL_NAME)
	local parkedModel = parkingFolder:FindFirstChild(APPRAISER_MODEL_NAME)
	local model = nil

	if workspaceModel and workspaceModel:IsA("Model") then
		model = workspaceModel
		self._workspaceParent = workspaceModel.Parent
	elseif parkedModel and parkedModel:IsA("Model") then
		model = parkedModel
	end

	if not self._workspaceParent then
		self._workspaceParent = Workspace
	end

	self._appraiserModel = model
end

function AppraisalService:_setNpcActive(isActive: boolean)
	self:_ensureNpcResolved()

	local appraiserModel = self._appraiserModel
	if not (appraiserModel and appraiserModel.Parent) then
		return
	end

	if isActive then
		local targetParent = self._workspaceParent or Workspace
		if appraiserModel.Parent ~= targetParent then
			appraiserModel.Parent = targetParent
		end
		return
	end

	local parkingFolder = ensureParkingFolder()
	if appraiserModel.Parent ~= parkingFolder then
		appraiserModel.Parent = parkingFolder
	end
end

function AppraisalService:_broadcastState()
	ensureUpdatedRemote():FireAllClients(AppraisalState.CloneState(self._state))
end

function AppraisalService:_reconcileState(shouldBroadcast: boolean?): any
	self:_ensureNpcResolved()

	local now = Workspace:GetServerTimeNow()
	if self._forcedActiveUntil > 0 and now >= self._forcedActiveUntil then
		self._forcedActiveUntil = 0
	end

	local nextCycleId = math.floor(now / AppraisalConfig.cycleIntervalSeconds)
	if self._cycleId ~= nextCycleId then
		self._cycleId = nextCycleId
		self._stockRemaining = AppraisalConfig.stockPerSpawn
	end

	local nextState = AppraisalState.CloneState(buildCycleState(now, self._stockRemaining, self._forcedActiveUntil))
	local changed = not AppraisalState.AreEqual(self._state, nextState)
	self._state = nextState
	self:_setNpcActive(nextState.isActive)

	if changed and shouldBroadcast ~= false then
		self:_broadcastState()
	end

	return self._state
end

function AppraisalService:ForceAppear(durationSeconds: number?)
	local now = Workspace:GetServerTimeNow()
	local resolvedDuration = math.max(1, math.floor(tonumber(durationSeconds) or AppraisalConfig.activeDurationSeconds))
	self._forcedActiveUntil = math.max(self._forcedActiveUntil or 0, now + resolvedDuration)
	return self:_reconcileState(true)
end

function AppraisalService:GetState(_player: Player)
	return response(true, "Loaded appraisal state.", self:_reconcileState(false))
end

function AppraisalService:PerformAppraisal(player: Player, payload: any)
	local state = self:_reconcileState(false)
	if not state.isActive then
		return response(false, "The appraiser is unavailable right now.", state)
	end
	if state.stockRemaining <= 0 then
		return response(false, "The appraiser is out of service stock.", state)
	end
	if typeof(payload) ~= "table" then
		return response(false, "Appraisal payload must be a table.", state)
	end

	local region = payload.region
	if typeof(region) ~= "string" or not BodyPartRegions.IsValid(region) then
		return response(false, "A valid region is required.", state)
	end

	local ownedId = payload.ownedId
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return response(false, "ownedId is required.", state)
	end

	local equippedState = BodyPartService:GetSessionLoadout(player)
	local equippedEntry = equippedState[region]
	if not equippedEntry then
		return response(false, "There is no equipped body part in that slot.", state)
	end
	if equippedEntry.ownedId ~= ownedId then
		return response(false, "That equipped body part changed. Select it again before appraising.", state)
	end

	local ownedRecord = DataService:GetOwnedBodyParts(player)[ownedId]
	if not ownedRecord then
		return response(false, "You do not own that body part anymore.", state)
	end

	local piece = BodyPartsCatalog.GetPiece(ownedRecord.pieceId)
	if not piece then
		return response(false, "That body part is no longer configured.", state)
	end

	local appraisalCost = AppraisalPricing.GetCost(ownedRecord, piece)
	local currentMoney = DataService:GetMoney(player)
	if currentMoney < appraisalCost then
		return response(
			false,
			"You don't have enough money to appraise this body part.",
			state,
			nil,
			"INSUFFICIENT_MONEY"
		)
	end

	local previousMoney = currentMoney
	local updatedMoney = DataService:AddMoney(player, -appraisalCost, "appraisal_cost")
	if updatedMoney > previousMoney then
		return response(false, "Could not process the appraisal payment.", state)
	end

	local previousVariantSnapshot = {
		mutationId = ownedRecord.mutationId,
		mutation = ownedRecord.mutation,
		mutationMultiplier = ownedRecord.mutationMultiplier,
		sizeId = ownedRecord.sizeId,
		sizeMultiplier = ownedRecord.sizeMultiplier,
		variantMultiplier = ownedRecord.variantMultiplier,
		finalPassiveIncomePerSecond = ownedRecord.finalPassiveIncomePerSecond,
	}

	local randomSource = Random.new()
	local mutationRoll = chooseWeightedEntry(randomSource, AppraisalConfig.mutationWeights)
	local mutationData = MutationConfig.Get(if mutationRoll then mutationRoll.id else nil) or MutationConfig.GetDefault()
	local sizeRoll = chooseWeightedEntry(randomSource, AppraisalConfig.sizeWeights)
	local sizeData = SizeConfig.Get(if sizeRoll then sizeRoll.id else nil) or SizeConfig.GetDefault()
	local sizeScale = SizeConfig.RollScale(randomSource, sizeData)
	local sizeMoneyMultiplier = SizeConfig.GetMoneyMultiplier(sizeData.id)
	local variantMultiplier = RollMath.ComputeVariantMultiplier(mutationData.multiplier, sizeMoneyMultiplier)
	local finalPassiveIncomePerSecond = RollMath.ComputeFinalPassiveIncome(piece.passiveIncomePerSecond, variantMultiplier)

	local updatedRecord, updateError = DataService:UpdateOwnedBodyPartVariant(player, ownedId, {
		mutationId = mutationData.id,
		mutation = mutationData.displayName,
		mutationMultiplier = mutationData.multiplier,
		sizeId = sizeData.id,
		sizeMultiplier = sizeScale,
		variantMultiplier = variantMultiplier,
		finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
	})
	if not updatedRecord then
		DataService:AddMoney(player, appraisalCost, "other")
		return response(false, updateError or "The appraisal could not be completed.", state)
	end

	local refreshed, refreshMessage = BodyPartService:RefreshEquippedOwnedBodyPartVariant(player, ownedId, sizeScale)
	if not refreshed then
		DataService:UpdateOwnedBodyPartVariant(player, ownedId, previousVariantSnapshot)
		DataService:AddMoney(player, appraisalCost, "other")
		return response(false, refreshMessage or "The body part visuals could not be refreshed.", state)
	end

	self._stockRemaining = math.max(0, self._stockRemaining - 1)
	local nextState = self:_reconcileState(true)

	return response(true, "Appraisal complete.", nextState, {
		ownedId = ownedId,
		region = region,
		pieceId = piece.id,
		before = buildAppraisalSnapshot(ownedRecord, piece),
		after = buildAppraisalSnapshot(updatedRecord, piece),
	})
end

function AppraisalService:OnStart()
	if self._started then
		return
	end

	self._started = true
	getStateRemote = ensureRemoteFunction(getStateRemote, GET_STATE_REMOTE_NAME)
	performAppraisalRemote = ensureRemoteFunction(performAppraisalRemote, PERFORM_APPRAISAL_REMOTE_NAME)
	updatedRemote = ensureUpdatedRemote()

	getStateRemote.OnServerInvoke = function(player: Player)
		return self:GetState(player)
	end

	performAppraisalRemote.OnServerInvoke = function(player: Player, payload: any)
		return self:PerformAppraisal(player, payload)
	end

	self:_reconcileState(false)

	task.spawn(function()
		while true do
			self:_reconcileState(true)
			task.wait(1)
		end
	end)
end

return AppraisalService
