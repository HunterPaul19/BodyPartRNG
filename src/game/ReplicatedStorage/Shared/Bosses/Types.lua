export type BossMoveTag = string

export type BossTargetContext = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	distanceToBoss: number,
	distanceToHome: number,
}

export type BossMoveDefinition = {
	id: string,
	tags: { string },
	cooldownSeconds: number,
	minRange: number,
	maxRange: number,
	weight: number,
	rootDuringCast: boolean,
	castTimeSeconds: number,
	recoverySeconds: number,
	module: any,
	moduleId: string,
}

export type BossDefinition = {
	bossId: string,
	displayName: string,
	arenaId: string,
	scaleMultiplier: number,
	walkSpeed: number,
	aggroRadius: number,
	leashRadius: number,
	retargetCadenceSeconds: number,
	abilityCadenceSeconds: number,
	retargetSwapBuffer: number,
	moveToRefreshSeconds: number,
	moves: { BossMoveDefinition },
}

export type BossRuntimeContext = {
	now: number,
	bossDefinition: BossDefinition,
	move: BossMoveDefinition,
	bossModel: Model,
	bossHumanoid: Humanoid,
	bossRootPart: BasePart,
	bossState: string,
	homePosition: Vector3,
	targetPlayer: Player?,
	targetCharacter: Model?,
	targetHumanoid: Humanoid?,
	targetRootPart: BasePart?,
	distanceToTarget: number?,
	aliveTargets: { BossTargetContext },
}

export type BossMoveModule = {
	CanUse: (context: BossRuntimeContext) -> (boolean, string?),
	GetTargeting: (context: BossRuntimeContext) -> { [string]: any },
	ExecuteStub: (context: BossRuntimeContext) -> { [string]: any },
}

return table.freeze({})
