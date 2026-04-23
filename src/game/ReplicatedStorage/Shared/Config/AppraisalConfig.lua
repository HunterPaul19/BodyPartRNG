local AppraisalConfig = {
	successSoundName = "AppraisalSuccess",
	mutationWeights = table.freeze({
		table.freeze({
			id = "none",
			weight = 99.5,
		}),
		table.freeze({
			id = "diamond",
			weight = 0.60,
		}),
		table.freeze({
			id = "magma",
			weight = 0.24,
		}),
		table.freeze({
			id = "corrupted",
			weight = 0.12,
		}),
		table.freeze({
			id = "prismatic",
			weight = 0.04,
		}),
	}),
	sizeWeights = table.freeze({
		table.freeze({
			id = "tiny",
			weight = 12,
		}),
		table.freeze({
			id = "small",
			weight = 18,
		}),
		table.freeze({
			id = "normal",
			weight = 40,
		}),
		table.freeze({
			id = "large",
			weight = 18,
		}),
		table.freeze({
			id = "huge",
			weight = 9,
		}),
		table.freeze({
			id = "titanic",
			weight = 3,
		}),
	}),
}

return table.freeze(AppraisalConfig)
