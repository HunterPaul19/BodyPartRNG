local Constants = {
	REMOTES_FOLDER_NAME = "Remotes",
	COMBAT_REMOTES_FOLDER_NAME = "CombatPhysics",
	REMOTE_NAMES = {
		KnockbackDispatch = "KnockbackDispatch",
		KnockbackResult = "KnockbackResult",
		KnockbackObserverDispatch = "KnockbackObserverDispatch",
	},
	COLLISION_GROUPS = {
		BodyPhysics = "CombatBodyPhysics",
		Hitbox = "CombatHitbox",
		HitboxNoCollide = "CombatHitboxNoCollide",
		Ragdoll = "CombatRagdoll",
	},
}

Constants.REMOTE_NAMES = table.freeze(Constants.REMOTE_NAMES)
Constants.COLLISION_GROUPS = table.freeze(Constants.COLLISION_GROUPS)

return table.freeze(Constants)
