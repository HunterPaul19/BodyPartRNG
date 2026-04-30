local AdminActionRegistry = {}

AdminActionRegistry.Risk = table.freeze({
	Safe = "safe",
	Mutating = "mutating",
	Destructive = "destructive",
})

AdminActionRegistry.Environment = table.freeze({
	StudioOnly = "studio_only",
	Any = "any",
})

local function numberField(id: string, label: string, placeholder: string, defaultValue: string?): any
	return {
		id = id,
		label = label,
		kind = "number",
		placeholder = placeholder,
		defaultValue = defaultValue or "",
	}
end

local function textField(id: string, label: string, placeholder: string, defaultValue: string?): any
	return {
		id = id,
		label = label,
		kind = "string",
		placeholder = placeholder,
		defaultValue = defaultValue or "",
	}
end

local function playerField(id: string?): any
	return {
		id = id or "userId",
		label = "Target UserId",
		kind = "player",
		placeholder = "Selected player",
		defaultValue = "$selectedPlayerUserId",
	}
end

local function confirmationField(text: string): any
	return {
		id = "confirmation",
		label = string.format("Confirmation (%s)", text),
		kind = "string",
		placeholder = text,
		defaultValue = "",
	}
end

AdminActionRegistry.Tabs = {
	{
		id = "overview",
		title = "Overview",
		subtitle = "Server controls and test launch points.",
		pageName = "OverviewPage",
		sections = {
			{
				title = "Quick Actions",
				description = "High-level buttons for broad test coverage and smoke checks.",
				actions = {
					{
						id = "test_dialogue",
						title = "Test Dialogue",
						description = "Launch the sample merchant dialogue locally so the dialogue tree and shop handoff can be verified from the admin panel.",
						risk = AdminActionRegistry.Risk.Safe,
					},
					{
						id = "guide_to_crafting",
						title = "Guide To Crafting",
						description = "Show the local floor guide toward the crafting station so tutorial-style objective presentation can be tested.",
						risk = AdminActionRegistry.Risk.Safe,
					},
					{
						id = "show_merchant",
						title = "Show Merchant",
						description = "Force the timed merchant to appear immediately so the shop flow can be tested on demand.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							numberField("durationSeconds", "Duration Seconds", "300", "300"),
						},
					},
					{
						id = "set_nighttime",
						title = "Set Nighttime",
						description = "Jump the live day/night cycle to the configured nighttime phase for visibility and mood testing.",
						risk = AdminActionRegistry.Risk.Mutating,
					},
					{
						id = "refresh_server_state",
						title = "Refresh Server State",
						description = "Refresh admin-readable state snapshots for the current server.",
						risk = AdminActionRegistry.Risk.Safe,
					},
				},
			},
			{
				title = "Session Checks",
				description = "Useful slots for broad validation flows once systems are online.",
				actions = {
					{
						id = "run_smoke_test",
						title = "Run Smoke Test",
						description = "Run a quick environment and system health pass.",
						risk = AdminActionRegistry.Risk.Safe,
					},
					{
						id = "dump_session_summary",
						title = "Dump Session Summary",
						description = "Surface the current server's player, economy, roll, merchant, and place summary.",
						risk = AdminActionRegistry.Risk.Safe,
					},
				},
			},
		},
	},
	{
		id = "players",
		title = "Players",
		subtitle = "Player-scoped tools, targeting, and account checks.",
		pageName = "PlayersPage",
		sections = {
			{
				title = "Targeting",
				description = "Per-player admin tools for profile and state validation.",
				actions = {
					{
						id = "inspect_player_profile",
						title = "Inspect Player Profile",
						description = "View data, load state, and profile metadata for a selected player.",
						risk = AdminActionRegistry.Risk.Safe,
						fields = { playerField() },
					},
					{
						id = "repair_marketplace_entitlement",
						title = "Repair VIP+ Entitlement",
						description = "Verify the selected player owns VIP+ on Roblox, then repair the local entitlement and benefits state.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							textField("offerKey", "Offer Key", "vip_plus", "vip_plus"),
							textField("reason", "Reason", "admin repair", "admin repair"),
						},
					},
					{
						id = "reload_player_state",
						title = "Reload Player State",
						description = "Force a safe refresh of a player's replicated state.",
						risk = AdminActionRegistry.Risk.Safe,
						fields = { playerField() },
					},
					{
						id = "trigger_tutorial",
						title = "Trigger Tutorial",
						description = "Reset the selected player into tutorial replay state, optionally at a specific step id.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							textField("stepId", "Step ID", "blank = welcome", ""),
						},
					},
					{
						id = "arm_boss_tutorial",
						title = "Arm Boss Tutorial",
						description = "Set the selected player's next boss portal interaction to launch the one-time Flame Guard General tutorial arena.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = { playerField() },
					},
					{
						id = "teleport_to_player",
						title = "Teleport To Player",
						description = "Move your character next to the selected player.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = { playerField() },
					},
					{
						id = "bring_player",
						title = "Bring Player",
						description = "Move the selected player next to your character.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = { playerField() },
					},
					{
						id = "respawn_player",
						title = "Respawn Player",
						description = "Reload the selected player's character.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = { playerField() },
					},
				},
			},
			{
				title = "Moderation",
				description = "Live-gated player lifecycle commands.",
				actions = {
					{
						id = "kick_player",
						title = "Kick Player",
						description = "Disconnect a selected player.",
						risk = AdminActionRegistry.Risk.Destructive,
						requiresConfirmation = true,
						confirmationText = "KICK",
						fields = {
							playerField(),
							textField("reason", "Reason", "Admin action", "Admin action"),
							confirmationField("KICK"),
						},
					},
					{
						id = "reset_player_data",
						title = "Reset Player Data",
						description = "Wipe a selected player's progression profile and kick them to reload.",
						risk = AdminActionRegistry.Risk.Destructive,
						requiresConfirmation = true,
						confirmationText = "RESET",
						fields = {
							playerField(),
							confirmationField("RESET"),
						},
					},
				},
			},
		},
	},
	{
		id = "progression",
		title = "Progression",
		subtitle = "Economy, profile growth, and progression checkpoints.",
		pageName = "ProgressionPage",
		sections = {
			{
				title = "Economy",
				description = "Shortcuts for progression balancing and reward testing.",
				actions = {
					{
						id = "grant_money",
						title = "Grant Money",
						description = "Add or set test currency for the selected player.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							textField("mode", "Mode", "add or set", "add"),
							numberField("amount", "Amount", "1000", "1000"),
						},
					},
					{
						id = "add_time_shards",
						title = "Add Time Shards",
						description = "Add Time Shards to the selected player.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							numberField("amount", "Amount", "100", "100"),
						},
					},
					{
						id = "grant_potion",
						title = "Grant Potion",
						description = "Grant a configured potion by id.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							textField("potionId", "Potion ID", "luck3", "luck3"),
							numberField("amount", "Uses", "1", "1"),
						},
					},
					{
						id = "grant_all_potions",
						title = "Grant All Potions",
						description = "Give uses of every configured potion to your live profile.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							numberField("amount", "Uses Per Potion", "1", "1"),
						},
					},
					{
						id = "clear_all_potion_effects",
						title = "Remove All Potion Effects",
						description = "Clear every currently active potion effect from your live profile.",
						risk = AdminActionRegistry.Risk.Mutating,
					},
					{
						id = "set_time_played",
						title = "Set Time Played",
						description = "Fast-forward time-based progression values.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							numberField("seconds", "Seconds", "3600", "3600"),
						},
					},
				},
			},
			{
				title = "Progress Gates",
				description = "Milestone validation for roll sources, titles, and achievements.",
				actions = {
					{
						id = "set_roll_type",
						title = "Set Roll Source",
						description = "Set the selected roll source by roll type id.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							textField("rollTypeId", "Roll Type ID", "roll_2", "roll_2"),
						},
					},
					{
						id = "unlock_achievement",
						title = "Unlock Achievement",
						description = "Mark one achievement complete for the selected player.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							textField("achievementId", "Achievement ID", "warm_up_winner", "warm_up_winner"),
						},
					},
					{
						id = "equip_title",
						title = "Equip/Clear Title",
						description = "Equip a title id, or leave blank to clear the selected player's title.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							textField("titleId", "Title ID", "warm_up_winner", "warm_up_winner"),
						},
					},
				},
			},
		},
	},
	{
		id = "bodyParts",
		title = "Body Parts",
		subtitle = "Collection, modifiers, rarity, and roll output validation.",
		pageName = "BodyPartsPage",
		sections = {
			{
				title = "Collection Tools",
				description = "Targeted helpers for verifying body-part, accessory, and inventory state.",
				actions = {
					{
						id = "grant_body_part",
						title = "Grant Body Part",
						description = "Give a chosen body part directly to yourself.",
						risk = AdminActionRegistry.Risk.Mutating,
					},
					{
						id = "grant_head_accessory",
						title = "Grant Head Accessory",
						description = "Give a chosen head accessory directly to yourself.",
						risk = AdminActionRegistry.Risk.Mutating,
					},
					{
						id = "grant_gear_accessory",
						title = "Grant Gear Accessory",
						description = "Give a chosen gear accessory directly to yourself.",
						risk = AdminActionRegistry.Risk.Mutating,
					},
					{
						id = "grant_crafting_material",
						title = "Grant Crafting Material",
						description = "Give a chosen crafting material directly to yourself.",
						risk = AdminActionRegistry.Risk.Mutating,
					},
					{
						id = "grant_all_crafting_materials",
						title = "Grant All Crafting Materials",
						description = "Give every configured crafting material directly to yourself.",
						risk = AdminActionRegistry.Risk.Mutating,
					},
					{
						id = "grant_full_set",
						title = "Grant Full Set",
						description = "Grant every configured piece for a set id.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							textField("setId", "Set ID", "starter", ""),
						},
					},
					{
						id = "clear_body_parts",
						title = "Clear Unequipped Body Parts",
						description = "Remove all unequipped, unfavorited body parts from the selected player.",
						risk = AdminActionRegistry.Risk.Destructive,
						requiresConfirmation = true,
						confirmationText = "CLEAR",
						fields = {
							playerField(),
							confirmationField("CLEAR"),
						},
					},
					{
						id = "equip_best_loadout",
						title = "Equip Best Loadout",
						description = "Equip the selected player's best available loadout.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = { playerField() },
					},
				},
			},
			{
				title = "Modifier Validation",
				description = "Controls for testing rarity and modifier calculations.",
				actions = {
					{
						id = "force_modifier_roll",
						title = "Simulate Roll Batch",
						description = "Run a non-granting roll simulation using current or supplied luck inputs.",
						risk = AdminActionRegistry.Risk.Safe,
						fields = {
							playerField(),
							numberField("count", "Roll Count", "100", "100"),
							textField("rollTypeId", "Roll Type ID", "selected", ""),
							textField("rollRegion", "Roll Region", "selected", ""),
							numberField("totalLuck", "Override Luck", "blank = current", ""),
						},
					},
					{
						id = "preview_rarity_table",
						title = "Preview Rarity Table",
						description = "Show current rarity odds and tuning values.",
						risk = AdminActionRegistry.Risk.Safe,
					},
					{
						id = "inspect_loadout_bonuses",
						title = "Inspect Loadout Bonuses",
						description = "Inspect computed body part, aura, and potion bonuses for the selected player.",
						risk = AdminActionRegistry.Risk.Safe,
						fields = { playerField() },
					},
				},
			},
		},
	},
	{
		id = "cases",
		title = "Roll Sources",
		subtitle = "Roll source flows, configured tiers, and reward simulation.",
		pageName = "CasesPage",
		sections = {
			{
				title = "Roll Source Control",
				description = "Tools for testing configured roll tiers without inventing a separate case model.",
				actions = {
					{
						id = "inspect_roll_sources",
						title = "Inspect Roll Sources",
						description = "List configured roll types, costs, luck multipliers, and band scalars.",
						risk = AdminActionRegistry.Risk.Safe,
					},
					{
						id = "select_roll_source",
						title = "Select Roll Source",
						description = "Set the selected player's roll type.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							textField("rollTypeId", "Roll Type ID", "roll_2", "roll_2"),
						},
					},
				},
			},
			{
				title = "Reward Testing",
				description = "Deterministic and bulk reward validation against the current roll list.",
				actions = {
					{
						id = "simulate_case_batch",
						title = "Simulate Roll Batch",
						description = "Run bulk non-granting roll simulations for the current roll source.",
						risk = AdminActionRegistry.Risk.Safe,
						fields = {
							playerField(),
							numberField("count", "Roll Count", "1000", "1000"),
							textField("rollTypeId", "Roll Type ID", "selected", ""),
							textField("rollRegion", "Roll Region", "selected", ""),
						},
					},
					{
						id = "force_case_reward",
						title = "Grant Roll Result",
						description = "Grant one specific piece id as an admin roll-source reward.",
						risk = AdminActionRegistry.Risk.Mutating,
						fields = {
							playerField(),
							textField("pieceId", "Piece ID", "configured piece id", ""),
						},
					},
					{
						id = "preview_chest_opening",
						title = "Preview Chest Opening",
						description = "Open a preview-only chest sequence with inventory-style reward cards. This does not grant or save rewards.",
						risk = AdminActionRegistry.Risk.Safe,
						fields = {
							playerField(),
							textField("chestId", "Chest ID", "Basic, VIP, VIP+, BossTier1, BossTier2, BossTier3", "Basic"),
							numberField("count", "Reward Count", "5", "5"),
							textField("rollTypeId", "Roll Type ID", "selected or configured id", ""),
							textField("rollRegion", "Roll Region", "selected or region id", ""),
						},
					},
					{
						id = "trigger_daily_free_chest",
						title = "Trigger Daily Free Chest",
						description = "Grant real Daily Free Chest loot to yourself and open the Basic chest sequence. This does not touch daily claim state.",
						risk = AdminActionRegistry.Risk.Mutating,
					},
					{
						id = "trigger_vip_chest",
						title = "Trigger VIP Chest",
						description = "Grant real VIP Chest loot to yourself and open the VIP chest sequence. This ignores VIP ownership and does not touch daily claim state.",
						risk = AdminActionRegistry.Risk.Mutating,
					},
					{
						id = "trigger_vip_plus_chest",
						title = "Trigger VIP+ Chest",
						description = "Grant real VIP+ Chest loot to yourself and open the VIP+ chest sequence. This ignores VIP+ ownership and does not touch daily claim state.",
						risk = AdminActionRegistry.Risk.Mutating,
					},
				},
			},
		},
	},
	{
		id = "diagnostics",
		title = "Diagnostics",
		subtitle = "Logs, state snapshots, and environment inspection.",
		pageName = "DiagnosticsPage",
		sections = {
			{
				title = "Runtime",
				description = "Outputs for surfacing current game state and health.",
				actions = {
					{
						id = "capture_runtime_snapshot",
						title = "Capture Runtime Snapshot",
						description = "Collect a structured diagnostic snapshot.",
						risk = AdminActionRegistry.Risk.Safe,
					},
					{
						id = "test_pyramid_hitbox",
						title = "Test Pyramid Hitbox",
						description = "Spawn a visible square-pyramid hitbox from your character's head for quick combat volume validation.",
						risk = AdminActionRegistry.Risk.Safe,
					},
					{
						id = "view_recent_events",
						title = "View Recent Events",
						description = "List recent server-side admin and gameplay diagnostic events.",
						risk = AdminActionRegistry.Risk.Safe,
					},
					{
						id = "inspect_boss_arena",
						title = "Inspect Boss Arena",
						description = "Read current boss arena timer, health, and runtime state when available.",
						risk = AdminActionRegistry.Risk.Safe,
					},
				},
			},
			{
				title = "Replication",
				description = "Tooling for tracking networked and replicated state.",
				actions = {
					{
						id = "inspect_replication",
						title = "Inspect Replication",
						description = "Check replicated profile and UI data for the selected player.",
						risk = AdminActionRegistry.Risk.Safe,
						fields = { playerField() },
					},
					{
						id = "export_debug_payload",
						title = "Export Debug Payload",
						description = "Serialize diagnostic data for offline review.",
						risk = AdminActionRegistry.Risk.Safe,
						fields = { playerField() },
					},
				},
			},
		},
	},
}

local actionsByKey = {}

for _, tab in ipairs(AdminActionRegistry.Tabs) do
	for _, section in ipairs(tab.sections) do
		for _, action in ipairs(section.actions) do
			action.tabId = tab.id
			action.sectionTitle = section.title
			action.environment = action.environment or AdminActionRegistry.Environment.Any
			action.risk = action.risk or AdminActionRegistry.Risk.Safe
			actionsByKey[string.format("%s:%s", tab.id, action.id)] = action
		end
	end
end

function AdminActionRegistry.GetAction(tabId: string, actionId: string): any?
	return actionsByKey[string.format("%s:%s", tabId, actionId)]
end

return table.freeze(AdminActionRegistry)
