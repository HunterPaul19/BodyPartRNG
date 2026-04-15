local MutationConfig = require(script.Parent.MutationConfig)

local AppraisalConfig = {
	cycleIntervalSeconds = 900,
	activeDurationSeconds = 300,
	stockPerSpawn = 15,
	mutationWeights = MutationConfig.GetOrdered(),
	sizeWeights = table.freeze({
		table.freeze({
			id = "tiny",
			weight = 8,
		}),
		table.freeze({
			id = "small",
			weight = 5,
		}),
		table.freeze({
			id = "normal",
			weight = 60,
		}),
		table.freeze({
			id = "large",
			weight = 18,
		}),
		table.freeze({
			id = "huge",
			weight = 6,
		}),
		table.freeze({
			id = "titanic",
			weight = 3,
		}),
	}),
}

return table.freeze(AppraisalConfig)
