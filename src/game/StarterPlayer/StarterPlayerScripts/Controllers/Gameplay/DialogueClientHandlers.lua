local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local Registry = require(ReplicatedStorage.Shared.Gameplay.Dialogue.Registry)
local Schema = require(ReplicatedStorage.Lists.Schema)

local DataController = require(script.Parent.DataController)
local DialogueController = require(script.Parent.DialogueController)
local FrameController = require(script.Parent.FrameController)
local MerchantPresentationController = require(script.Parent.MerchantPresentationController)

local DEFAULT_SHOP_FRAME_NAME = "ShopUI"
local VIP_OWNED_KEY = Schema.VipOwned and Schema.VipOwned.key or nil

local registered = false

local DialogueClientHandlers = {}

local function toBoolean(value: any): boolean
	return value == true
end

local function getContextInstance(context: { [string]: any }?, key: string): Instance?
	if typeof(context) ~= "table" then
		return nil
	end

	local value = context[key]
	if typeof(value) == "Instance" then
		return value
	end

	return nil
end

local function openFrameWithPresentation(session, frameName: string, context: { [string]: any }?)
	session.closeDialogue(function()
		local shouldUseMerchantPresentation = context ~= nil
			and typeof(context.dialogueFrameName) == "string"
			and context.dialogueFrameName ~= ""

		if shouldUseMerchantPresentation then
			local dialogueCameraPart = getContextInstance(context, "dialogueCameraPart")
			local sourceInstance = getContextInstance(context, "sourceInstance")
			local speakerModel = getContextInstance(context, "speakerModel")
			local opened = MerchantPresentationController:Open(frameName, {
				cameraPart = if dialogueCameraPart and dialogueCameraPart:IsA("BasePart") then dialogueCameraPart else nil,
				sourceInstance = sourceInstance,
				interactionType = if context and typeof(context.interactionType) == "string" then context.interactionType else nil,
				speakerModel = if speakerModel and speakerModel:IsA("Model") then speakerModel else nil,
			})
			if opened then
				return
			end
		end

		FrameController:OpenFrame(frameName)
	end)
end

function DialogueClientHandlers.Register()
	if registered then
		return
	end
	registered = true

	DialogueController.SetBeforeOpenHook(function()
		local openFrameName = FrameController:GetOpenFrame()
		if not openFrameName then
			return 0
		end

		FrameController:CloseFrame()
		return FrameController.CloseTween.Time
	end)

	DialogueController.SetPortraitResolver(function(context)
		if typeof(context) == "table" then
			local speakerModel = context.speakerModel
			if typeof(speakerModel) == "Instance" and speakerModel:IsA("Model") then
				return speakerModel
			end
		end

		return BodyPartsCatalog.GetDefaultBaseRig()
	end)

	DialogueController.RegisterRefreshSignal(DataController.DataReceived)
	DialogueController.RegisterRefreshSignal(DataController.DataUpdated)

	Registry.RegisterAction("gotoNode", function(session, choice, action)
		local nextNodeId = action.nextNodeId or choice.nextNodeId
		if typeof(nextNodeId) ~= "string" or nextNodeId == "" then
			return false
		end

		return session.setCurrentNode(nextNodeId)
	end)

	Registry.RegisterAction("closeDialogue", function(session)
		session.closeDialogue()
		return true
	end)

	Registry.RegisterAction("openFrame", function(session, _choice, action)
		local context = session.context
		local frameName = action.frameName or (context and context.dialogueFrameName)
		if typeof(frameName) ~= "string" or frameName == "" then
			return false
		end

		openFrameWithPresentation(session, frameName, context)
		return true
	end)

	Registry.RegisterAction("openShopFrame", function(session, _choice, action)
		local context = session.context
		local frameName = action.frameName or (context and context.dialogueFrameName) or DEFAULT_SHOP_FRAME_NAME
		if typeof(frameName) ~= "string" or frameName == "" then
			return false
		end

		openFrameWithPresentation(session, frameName, context)
		return true
	end)

	Registry.RegisterCondition("vipOwned", function()
		if not VIP_OWNED_KEY then
			return false
		end

		return toBoolean(DataController:Get(VIP_OWNED_KEY))
	end)
end

return DialogueClientHandlers
