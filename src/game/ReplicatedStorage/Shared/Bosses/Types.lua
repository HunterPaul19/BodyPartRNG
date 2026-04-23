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
	displayName: string,
	tags: { string },
	cooldownSeconds: number,
	weight: number,
	rootDuringCast: boolean,
	faceTargetOnCast: boolean,
	castTimeSeconds: number,
	recoverySeconds: number,
	animationFolderName: string?,
	module: any,
	moduleId: string,
}

export type BossDefinition = {
	bossId: string,
	displayName: string,
	arenaId: string,
	recommendedCombatScore: number,
	baseHealth: number,
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

export type BossEncounterScaling = {
	partySize: number,
	healthMultiplier: number,
	damageMultiplier: number,
}

export type BossRuntimeContext = {
	now: number,
	castId: string,
	bossDefinition: BossDefinition,
	encounterScaling: BossEncounterScaling,
	move: BossMoveDefinition,
	bossModel: Model,
	bossHumanoid: Humanoid,
	bossRootPart: BasePart,
	bossState: string,
	homePosition: Vector3,
	arenaModel: Model,
	floorRaycastRoots: { Instance },
	targetPlayer: Player?,
	targetCharacter: Model?,
	targetHumanoid: Humanoid?,
	targetRootPart: BasePart?,
	distanceToTarget: number?,
	aliveTargets: { BossTargetContext },
	EmitPresentation: (action: string, payload: { [string]: any }?) -> (),
}

export type BossCastLifecycleHandle = {
	Cancel: () -> (),
	IsComplete: () -> boolean,
	GetRecoveryEndsAt: (() -> number?)?,
}

export type BossMoveModule = {
	CanUse: (context: BossRuntimeContext) -> (boolean, string?),
	GetTargeting: (context: BossRuntimeContext) -> { [string]: any },
	ExecuteStub: (context: BossRuntimeContext) -> { [string]: any },
	StartCast: ((context: BossRuntimeContext) -> BossCastLifecycleHandle?)?,
	GetSelectionWeight: ((context: BossRuntimeContext) -> number?)?,
}

return table.freeze({})
