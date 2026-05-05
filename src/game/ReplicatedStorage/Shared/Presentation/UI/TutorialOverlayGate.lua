local TutorialOverlayGate = {}

export type ReleaseBlock = () -> ()

local nextBlockId = 0
local activeBlocks: { [number]: string } = {}

function TutorialOverlayGate.BeginBlock(reason: string?): ReleaseBlock
	nextBlockId += 1
	local blockId = nextBlockId
	local released = false

	activeBlocks[blockId] = if typeof(reason) == "string" and reason ~= "" then reason else "tutorial_overlay"

	return function()
		if released then
			return
		end

		released = true
		activeBlocks[blockId] = nil
	end
end

function TutorialOverlayGate.IsBlocked(): boolean
	return next(activeBlocks) ~= nil
end

return table.freeze(TutorialOverlayGate)
