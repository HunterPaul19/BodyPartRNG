local function formatSummary(template: string, replacements: { [string]: string }): string
	local summary = template

	for key, value in pairs(replacements) do
		summary = string.gsub(summary, "{" .. key .. "}", value)
	end

	return summary
end

local function createExplicitBossMoveStub(spec: { [string]: any })
	local bossId = if typeof(spec.bossId) == "string" and spec.bossId ~= "" then spec.bossId else "Boss"
	local moveLabel = if typeof(spec.moveLabel) == "string" and spec.moveLabel ~= "" then spec.moveLabel else "Boss Move"
	local targetMode = if typeof(spec.targetMode) == "string" and spec.targetMode ~= "" then spec.targetMode else "single"
	local summaryTemplate = if typeof(spec.summaryTemplate) == "string" and spec.summaryTemplate ~= ""
		then spec.summaryTemplate
		else "{moveLabel}"
	local description = if typeof(spec.description) == "string" and spec.description ~= ""
		then spec.description
		else summaryTemplate

	local moveModule = {}

	function moveModule.CanUse(context)
		if typeof(context) ~= "table" then
			return false, "Missing runtime context"
		end

		if targetMode == "single" or targetMode == "wide_area" then
			if context.targetPlayer == nil or context.targetRootPart == nil then
				return false, "No focus target"
			end
		elseif targetMode == "all_players" or targetMode == "none" then
			if typeof(context.aliveTargets) ~= "table" or #context.aliveTargets <= 0 then
				return false, "No alive players"
			end
		end

		return true
	end

	function moveModule.GetTargeting(context)
		local targetPlayerNames = {}
		for _, targetContext in ipairs(context.aliveTargets or {}) do
			table.insert(targetPlayerNames, targetContext.player.Name)
		end

		local targetName = if context.targetPlayer then context.targetPlayer.Name else "arena"
		local replacements = {
			bossId = bossId,
			moveLabel = moveLabel,
			target = targetName,
			targets = table.concat(targetPlayerNames, ", "),
		}

		local resolvedSummary = formatSummary(summaryTemplate, replacements)
		local targetCount = 0
		local resolvedTargetNames = {}

		if targetMode == "all_players" then
			targetCount = #targetPlayerNames
			resolvedTargetNames = targetPlayerNames
		elseif targetMode == "single" or targetMode == "wide_area" then
			targetCount = if context.targetPlayer then 1 else 0
			resolvedTargetNames = if context.targetPlayer then { targetName } else {}
		end

		return {
			bossId = bossId,
			mode = targetMode,
			targetCount = targetCount,
			targetPlayerNames = resolvedTargetNames,
			summary = resolvedSummary,
		}
	end

	function moveModule.ExecuteStub(context)
		local targeting = moveModule.GetTargeting(context)

		return {
			bossId = bossId,
			moveLabel = moveLabel,
			targetMode = targetMode,
			targetingSummary = targeting.summary,
			description = description,
		}
	end

	return table.freeze(moveModule)
end

return createExplicitBossMoveStub
