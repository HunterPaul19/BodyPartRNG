local ReplicatedStorage = game:GetService("ReplicatedStorage")

local createBossStubMove = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateBossStubMove)

return createBossStubMove({
	moveLabel = "Boss M1",
	targetMode = "single",
	summaryTemplate = "{moveLabel} -> {target}",
})
