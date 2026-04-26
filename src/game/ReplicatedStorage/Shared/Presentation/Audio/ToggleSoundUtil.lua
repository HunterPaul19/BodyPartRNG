local SoundUtil = require(script.Parent.SoundUtil)

local ToggleSoundUtil = {}

local SUPPRESS_DEFAULT_CLICK_SOUND_ATTRIBUTE = "SuppressDefaultClickSound"
local TOGGLE_ON_SOUND_NAME = "ToggleOn"
local TOGGLE_OFF_SOUND_NAME = "ToggleOff"

function ToggleSoundUtil.MarkToggleButton(button: GuiButton?): GuiButton?
	if not button then
		return nil
	end

	button:SetAttribute(SUPPRESS_DEFAULT_CLICK_SOUND_ATTRIBUTE, true)
	return button
end

function ToggleSoundUtil.ShouldSuppressDefaultClickSound(button: GuiButton?): boolean
	return button ~= nil and button:GetAttribute(SUPPRESS_DEFAULT_CLICK_SOUND_ATTRIBUTE) == true
end

function ToggleSoundUtil.PlayToggle(nextEnabled: boolean, parent: Instance?): Sound?
	return SoundUtil.Play(if nextEnabled then TOGGLE_ON_SOUND_NAME else TOGGLE_OFF_SOUND_NAME, parent)
end

return ToggleSoundUtil
