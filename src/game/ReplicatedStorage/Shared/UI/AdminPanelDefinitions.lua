local AdminPanelDefinitions = {}

AdminPanelDefinitions.Tabs = {
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
					},
					{
						id = "show_appraiser",
						title = "Show Appraiser",
						description = "Force the appraiser to appear immediately so the appraisal flow can be tested on demand.",
					},
					{
						id = "refresh_server_state",
						title = "Refresh Server State",
						description = "Placeholder for forcing a server-wide refresh of tracked gameplay state.",
					},
					{
						id = "broadcast_admin_notice",
						title = "Broadcast Admin Notice",
						description = "Placeholder for sending a visible test announcement to all connected players.",
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
						description = "Placeholder for a quick environment and system health pass.",
					},
					{
						id = "dump_session_summary",
						title = "Dump Session Summary",
						description = "Placeholder for surfacing the current server's test summary.",
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
						description = "Placeholder for viewing data, load state, and profile metadata for a selected player.",
					},
					{
						id = "reload_player_state",
						title = "Reload Player State",
						description = "Placeholder for forcing a safe refresh of a player's replicated state.",
					},
				},
			},
			{
				title = "Moderation",
				description = "Reserved slots for admin-only player lifecycle commands.",
				actions = {
					{
						id = "kick_player",
						title = "Kick Player",
						description = "Placeholder for disconnecting a selected player during testing.",
					},
					{
						id = "reset_player_data",
						title = "Reset Player Data",
						description = "Placeholder for wiping or rebuilding a selected player's progression profile.",
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
				description = "Future shortcuts for progression balancing and reward testing.",
				actions = {
					{
						id = "grant_money",
						title = "Grant Money",
						description = "Placeholder for giving test currency to the selected player.",
					},
					{
						id = "set_time_played",
						title = "Set Time Played",
						description = "Placeholder for fast-forwarding time-based progression values.",
					},
				},
			},
			{
				title = "Progress Gates",
				description = "Reserved hooks for unlocking milestones and validating balance.",
				actions = {
					{
						id = "unlock_progression_step",
						title = "Unlock Progression Step",
						description = "Placeholder for unlocking the next progression milestone.",
					},
					{
						id = "reset_progression_step",
						title = "Reset Progression Step",
						description = "Placeholder for rolling progression back to a known checkpoint.",
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
				description = "Targeted helpers for verifying body-part acquisition and inventory state.",
				actions = {
					{
						id = "grant_body_part",
						title = "Grant Body Part",
						description = "Placeholder for giving a chosen body part directly to a player.",
					},
					{
						id = "clear_body_parts",
						title = "Clear Body Parts",
						description = "Placeholder for resetting the player's current body-part inventory.",
					},
				},
			},
			{
				title = "Modifier Validation",
				description = "Future controls for testing rarity and modifier calculations.",
				actions = {
					{
						id = "force_modifier_roll",
						title = "Force Modifier Roll",
						description = "Placeholder for simulating a body part roll with explicit modifier inputs.",
					},
					{
						id = "preview_rarity_table",
						title = "Preview Rarity Table",
						description = "Placeholder for showing the current rarity odds and tuning values.",
					},
				},
			},
		},
	},
	{
		id = "cases",
		title = "Cases",
		subtitle = "Case-opening flows, unlocks, and reward source testing.",
		pageName = "CasesPage",
		sections = {
			{
				title = "Case Control",
				description = "Reserved actions for testing case progression and availability.",
				actions = {
					{
						id = "unlock_case",
						title = "Unlock Case",
						description = "Placeholder for unlocking a case tier for a player.",
					},
					{
						id = "grant_case_uses",
						title = "Grant Case Uses",
						description = "Placeholder for adding case openings or tickets for testing.",
					},
				},
			},
			{
				title = "Reward Testing",
				description = "Future controls for deterministic reward validation.",
				actions = {
					{
						id = "force_case_reward",
						title = "Force Case Reward",
						description = "Placeholder for forcing a specific reward from a chosen case.",
					},
					{
						id = "simulate_case_batch",
						title = "Simulate Case Batch",
						description = "Placeholder for running bulk case reward simulations.",
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
				description = "Reserved outputs for surfacing current game state and health.",
				actions = {
					{
						id = "capture_runtime_snapshot",
						title = "Capture Runtime Snapshot",
						description = "Placeholder for collecting a structured diagnostic snapshot.",
					},
					{
						id = "view_recent_events",
						title = "View Recent Events",
						description = "Placeholder for listing recent server-side gameplay events.",
					},
				},
			},
			{
				title = "Replication",
				description = "Future tooling for tracking networked and replicated state.",
				actions = {
					{
						id = "inspect_replication",
						title = "Inspect Replication",
						description = "Placeholder for checking replicated profile and UI data.",
					},
					{
						id = "export_debug_payload",
						title = "Export Debug Payload",
						description = "Placeholder for serializing diagnostic data for offline review.",
					},
				},
			},
		},
	},
}

AdminPanelDefinitions.TabsById = {}
AdminPanelDefinitions.ActionsById = {}

for _, tab in ipairs(AdminPanelDefinitions.Tabs) do
	AdminPanelDefinitions.TabsById[tab.id] = tab

	for _, section in ipairs(tab.sections) do
		for _, action in ipairs(section.actions) do
			AdminPanelDefinitions.ActionsById[string.format("%s:%s", tab.id, action.id)] = {
				tabId = tab.id,
				actionId = action.id,
				title = action.title,
				description = action.description,
				sectionTitle = section.title,
			}
		end
	end
end

return AdminPanelDefinitions
