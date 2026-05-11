local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local SocialService = game:GetService("SocialService")

local LOCAL_PLAYER = Players.LocalPlayer
local MAILBOX_FEEDBACK_PROMPT_TAG = "MailboxFeedbackPrompt"

local MailboxFeedbackController = {
	_started = false,
	_promptInFlight = false,
	_connections = {} :: { RBXScriptConnection },
}

function MailboxFeedbackController:_promptForFeedback()
	if self._promptInFlight then
		return
	end

	self._promptInFlight = true

	task.spawn(function()
		local ok, errorMessage = pcall(function()
			SocialService:PromptFeedbackSubmissionAsync()
		end)

		self._promptInFlight = false

		if not ok then
			Logger.Warn(string.format(
				"[MailboxFeedbackController] Failed to open feedback prompt: %s",
				tostring(errorMessage)
			))
		end
	end)
end

function MailboxFeedbackController:_handlePromptTriggered(prompt: ProximityPrompt, player: Player?)
	if player and player ~= LOCAL_PLAYER then
		return
	end

	if not CollectionService:HasTag(prompt, MAILBOX_FEEDBACK_PROMPT_TAG) then
		return
	end

	self:_promptForFeedback()
end

function MailboxFeedbackController:OnStart()
	if self._started then
		return
	end

	self._started = true

	table.insert(self._connections, ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player?)
		self:_handlePromptTriggered(prompt, player)
	end))
end

return MailboxFeedbackController
