local LegacyIds = {}

local SET_ID_MIGRATIONS = {
	brick_body_r6 = "rig",
	israeli_baszucki = "davy_bazooka",
}

local PIECE_ID_MIGRATIONS = {
	brick_body_r6_head = "rig_head",
	brick_body_r6_torso = "rig_torso",
	brick_body_r6_left_arm = "rig_left_arm",
	brick_body_r6_right_arm = "rig_right_arm",
	brick_body_r6_left_leg = "rig_left_leg",
	brick_body_r6_right_leg = "rig_right_leg",
	israeli_baszucki_head = "davy_bazooka_head",
	israeli_baszucki_torso = "davy_bazooka_torso",
	israeli_baszucki_left_arm = "davy_bazooka_left_arm",
	israeli_baszucki_right_arm = "davy_bazooka_right_arm",
	israeli_baszucki_left_leg = "davy_bazooka_left_leg",
	israeli_baszucki_right_leg = "davy_bazooka_right_leg",
}

function LegacyIds.NormalizeSetId(setId: string?): string?
	if typeof(setId) ~= "string" or setId == "" then
		return nil
	end

	return SET_ID_MIGRATIONS[setId] or setId
end

function LegacyIds.NormalizePieceId(pieceId: string?): string?
	if typeof(pieceId) ~= "string" or pieceId == "" then
		return nil
	end

	return PIECE_ID_MIGRATIONS[pieceId] or pieceId
end

return table.freeze(LegacyIds)
