local function createBossStubMove(spec: { [string]: any })
	local moveLabel = if typeof(spec.moveLabel) == "string" and spec.moveLabel ~= "" then spec.moveLabel else "Boss Move"
	local targetMode = if typeof(spec.targetMode) == "string" and spec.targetMode ~= "" then spec.targetMode else "single"
	local summaryTemplate = if typeof(spec.summaryTemplate) == "string" and spec.summaryTemplate ~= ""
		then spec.summaryTemplate
		else "{moveLabel}"

	local moveModule = {}

	function moveModule.CanUse(context)
		if typeof(context) ~= "table" then
			return false, "Missing runtime context"
		end

		if targetMode == "single" or targetMode == "wide_area" then
			if context.targetPlayer == nil or context.targetRootPart == nil then
				return false, "No focus target"
			end
		elseif targetMode == "all_players" then
			if typeof(context.aliveTargets) ~= "table" or #context.aliveTargets <= 0 then
				return false, "No alive players"
			end
		elseif targetMode == "none" then
			if typeof(context.aliveTargets) ~= "table" or #context.aliveTargets <= 0 then
				return false, "No alive players"
			end
		end

		return true
	end

	function moveModule.GetTargeting(context)
		if targetMode == "all_players" then
			local targetPlayerNames = {}

			for _, targetContext in ipairs(context.aliveTargets or {}) do
				table.insert(targetPlayerNames, targetContext.player.Name)
			end

			return {
				mode = targetMode,
				targetCount = #targetPlayerNames,
				targetPlayerNames = targetPlayerNames,
				summary = string.format("%s -> [%s]", moveLabel, table.concat(targetPlayerNames, ", ")),
			}
		end

		if targetMode == "none" then
			local summary = summaryTemplate
			summary = string.gsub(summary, "{moveLabel}", moveLabel)

			return {
				mode = targetMode,
				targetCount = 0,
				targetPlayerNames = {},
				summary = summary,
			}
		end

		local targetPlayer = context.targetPlayer
		local targetName = if targetPlayer then targetPlayer.Name else "none"
		local summary = summaryTemplate
		summary = string.gsub(summary, "{moveLabel}", moveLabel)
		summary = string.gsub(summary, "{target}", targetName)

		return {
			mode = targetMode,
			targetCount = if targetPlayer then 1 else 0,
			targetPlayerNames = if targetPlayer then { targetName } else {},
			summary = summary,
		}
	end

	function moveModule.ExecuteStub(context)
		local targeting = moveModule.GetTargeting(context)

		return {
			moveLabel = moveLabel,
			targetMode = targetMode,
			targetingSummary = targeting.summary,
		}
	end

	return table.freeze(moveModule)
end

return createBossStubMove
