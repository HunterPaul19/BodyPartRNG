export type DialogueAction = {
	type: string,
	nextNodeId: string?,
	frameName: string?,
	payload: { [string]: any }?,
}

export type DialogueChoice = {
	id: string,
	text: string,
	nextNodeId: string?,
	action: DialogueAction?,
	conditionIds: { string }?,
	conditionBehavior: "hide" | "disable"?,
	disabledText: string?,
}

export type DialogueNode = {
	id: string,
	speakerName: string,
	text: string,
	choices: { DialogueChoice },
}

export type DialogueInitialNodeRule = {
	nodeId: string,
	conditionIds: { string },
}

export type DialogueDefinition = {
	id: string,
	rootNodeId: string,
	initialNodeRules: { DialogueInitialNodeRule }?,
	nodesById: { [string]: DialogueNode },
}

local definitionsById: { [string]: DialogueDefinition } = {
	stan_onboarding_paid_roll_intro = {
		id = "stan_onboarding_paid_roll_intro",
		rootNodeId = "intro",
		initialNodeRules = {
			{
				nodeId = "completed",
				conditionIds = { "stanBossIntroCompleted" },
			},
			{
				nodeId = "boss_ready",
				conditionIds = { "stanBossIntroReady" },
			},
			{
				nodeId = "boss_reminder",
				conditionIds = { "stanBossIntroActive" },
			},
			{
				nodeId = "boss_offer",
				conditionIds = { "stanBossIntroAvailable" },
			},
			{
				nodeId = "crafting_completed",
				conditionIds = { "stanCraftingIntroCompleted" },
			},
			{
				nodeId = "crafting_ready",
				conditionIds = { "stanCraftingIntroReady" },
			},
			{
				nodeId = "crafting_reminder",
				conditionIds = { "stanCraftingIntroActive" },
			},
			{
				nodeId = "crafting_offer",
				conditionIds = { "stanCraftingIntroAvailable" },
			},
			{
				nodeId = "appraisal_ready",
				conditionIds = { "stanAppraisalIntroReady" },
			},
			{
				nodeId = "appraisal_reminder",
				conditionIds = { "stanAppraisalIntroActive" },
			},
			{
				nodeId = "appraisal_offer",
				conditionIds = { "stanAppraisalIntroAvailable" },
			},
			{
				nodeId = "appraisal_completed",
				conditionIds = { "stanAppraisalIntroCompleted" },
			},
			{
				nodeId = "ready",
				conditionIds = { "stanPaidRollIntroReady" },
			},
			{
				nodeId = "reminder",
				conditionIds = { "stanPaidRollIntroActive" },
			},
		},
		nodesById = {
			intro = {
				id = "intro",
				speakerName = "Stan",
				text = "Hey there! I'm Stan. Let's get your first stronger roll going. We'll use a paid roll, look for a Clean-or-better body part, then equip it so your build starts scaling.",
				choices = {
					{
						id = "accept",
						text = "Let's do it!",
						conditionIds = { "stanPaidRollIntroAvailable" },
						action = {
							type = "acceptQuest",
							nextNodeId = "accepted",
							payload = {
								questId = "stan_paid_roll_intro",
								providerId = "stan",
								style = "positive",
							},
						},
					},
					{
						id = "reminder",
						text = "What should I do next?",
						conditionIds = { "stanPaidRollIntroActive" },
						action = {
							type = "gotoNode",
							nextNodeId = "reminder",
						},
					},
					{
						id = "ready",
						text = "I did it!",
						conditionIds = { "stanPaidRollIntroReady" },
						action = {
							type = "gotoNode",
							nextNodeId = "ready",
						},
					},
					{
						id = "completed",
						text = "Thanks for the boss tour!",
						conditionIds = { "stanBossIntroCompleted" },
						action = {
							type = "gotoNode",
							nextNodeId = "completed",
						},
					},
					{
						id = "boss_offer",
						text = "What's next?",
						conditionIds = { "stanBossIntroAvailable" },
						action = {
							type = "gotoNode",
							nextNodeId = "boss_offer",
						},
					},
					{
						id = "boss_reminder",
						text = "Remind me about bosses.",
						conditionIds = { "stanBossIntroActive" },
						action = {
							type = "gotoNode",
							nextNodeId = "boss_reminder",
						},
					},
					{
						id = "boss_ready",
						text = "I beat my first boss!",
						conditionIds = { "stanBossIntroReady" },
						action = {
							type = "gotoNode",
							nextNodeId = "boss_ready",
						},
					},
					{
						id = "crafting_offer",
						text = "What's next?",
						conditionIds = { "stanCraftingIntroAvailable" },
						action = {
							type = "gotoNode",
							nextNodeId = "crafting_offer",
						},
					},
					{
						id = "crafting_reminder",
						text = "Remind me about crafting.",
						conditionIds = { "stanCraftingIntroActive" },
						action = {
							type = "gotoNode",
							nextNodeId = "crafting_reminder",
						},
					},
					{
						id = "crafting_ready",
						text = "I crafted the Crown!",
						conditionIds = { "stanCraftingIntroReady" },
						action = {
							type = "gotoNode",
							nextNodeId = "crafting_ready",
						},
					},
					{
						id = "crafting_completed",
						text = "Thanks for the crafting tour!",
						conditionIds = { "stanCraftingIntroCompleted" },
						action = {
							type = "gotoNode",
							nextNodeId = "crafting_completed",
						},
					},
					{
						id = "appraisal_offer",
						text = "What's next?",
						conditionIds = { "stanAppraisalIntroAvailable" },
						action = {
							type = "gotoNode",
							nextNodeId = "appraisal_offer",
						},
					},
					{
						id = "appraisal_reminder",
						text = "Remind me about appraisal.",
						conditionIds = { "stanAppraisalIntroActive" },
						action = {
							type = "gotoNode",
							nextNodeId = "appraisal_reminder",
						},
					},
					{
						id = "appraisal_ready",
						text = "I learned appraisal!",
						conditionIds = { "stanAppraisalIntroReady" },
						action = {
							type = "gotoNode",
							nextNodeId = "appraisal_ready",
						},
					},
					{
						id = "appraisal_completed",
						text = "Thanks for the appraisal tour!",
						conditionIds = { "stanAppraisalIntroCompleted" },
						action = {
							type = "gotoNode",
							nextNodeId = "appraisal_completed",
						},
					},
					{
						id = "leave",
						text = "I'll be back soon.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			accepted = {
				id = "accepted",
				speakerName = "Stan",
				text = "Nice! Start with a paid roll. Better rolls give you a better shot at quality parts.",
				choices = {
					{
						id = "close",
						text = "On it!",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			reminder = {
				id = "reminder",
				speakerName = "Stan",
				text = "You're doing great. Use a paid roll, find something Clean or better, then equip it.",
				choices = {
					{
						id = "close",
						text = "Got it.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			ready = {
				id = "ready",
				speakerName = "Stan",
				text = "That's it! You used a better roll, found a Clean-or-better part, and equipped it. Come grab your chest.",
				choices = {
					{
						id = "claim",
						text = "Thanks, Stan!",
						action = {
							type = "claimQuest",
							payload = {
								questId = "stan_paid_roll_intro",
								providerId = "stan",
								closeDialogue = true,
								style = "positive",
							},
						},
					},
					{
						id = "later",
						text = "I'll grab it in a bit.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			appraisal_offer = {
				id = "appraisal_offer",
				speakerName = "Stan",
				text = "Nice work with your first stronger part. Next up, let's visit the Appraiser. They can reroll a body part's size and mutation, which can make a good part even better.",
				choices = {
					{
						id = "accept",
						text = "Show me appraisal!",
						action = {
							type = "acceptQuest",
							nextNodeId = "appraisal_accepted",
							payload = {
								questId = "stan_appraisal_intro",
								providerId = "stan",
								readyNodeId = "appraisal_ready",
								style = "positive",
							},
						},
					},
					{
						id = "later",
						text = "I'll check it out soon.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			appraisal_accepted = {
				id = "appraisal_accepted",
				speakerName = "Stan",
				text = "Perfect. Head over to the Appraiser and say hello. Then appraise one equipped body part to see how it changes.",
				choices = {
					{
						id = "close",
						text = "On my way!",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			appraisal_reminder = {
				id = "appraisal_reminder",
				speakerName = "Stan",
				text = "You're close. Talk to the Appraiser, then appraise one body part.",
				choices = {
					{
						id = "close",
						text = "Got it.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			appraisal_ready = {
				id = "appraisal_ready",
				speakerName = "Stan",
				text = "That's appraisal! You found the Appraiser and gave a body part a fresh roll. Come grab your chest.",
				choices = {
					{
						id = "claim",
						text = "Thanks, Stan!",
						action = {
							type = "claimQuest",
							payload = {
								questId = "stan_appraisal_intro",
								providerId = "stan",
								closeDialogue = true,
								style = "positive",
							},
						},
					},
					{
						id = "later",
						text = "I'll grab it in a bit.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			crafting_offer = {
				id = "crafting_offer",
				speakerName = "Stan",
				text = "Nice work with appraisal. Next up, let's visit the Crafter. Crafting lets you turn extra parts into recipes like the Holiday Crown, and opening a recipe shows what parts it needs.",
				choices = {
					{
						id = "accept",
						text = "Show me crafting!",
						action = {
							type = "acceptQuest",
							nextNodeId = "crafting_accepted",
							payload = {
								questId = "stan_crafting_intro",
								providerId = "stan",
								readyNodeId = "crafting_ready",
								style = "positive",
							},
						},
					},
					{
						id = "later",
						text = "I'll check it out soon.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			crafting_accepted = {
				id = "crafting_accepted",
				speakerName = "Stan",
				text = "Perfect. Head to the Crafter at the crafting station, say hello, open the Holiday Crown recipe, then craft it.",
				choices = {
					{
						id = "close",
						text = "On my way!",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			crafting_reminder = {
				id = "crafting_reminder",
				speakerName = "Stan",
				text = "You're close. Talk to the Crafter, open the Holiday Crown recipe, then craft the Crown.",
				choices = {
					{
						id = "close",
						text = "Got it.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			crafting_ready = {
				id = "crafting_ready",
				speakerName = "Stan",
				text = "That's crafting! You found the Crafter, opened the Crown recipe, and crafted your first Crown. Come grab your chest.",
				choices = {
					{
						id = "claim",
						text = "Thanks, Stan!",
						action = {
							type = "claimQuest",
							payload = {
								questId = "stan_crafting_intro",
								providerId = "stan",
								closeDialogue = true,
								style = "positive",
							},
						},
					},
					{
						id = "later",
						text = "I'll grab it in a bit.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			boss_offer = {
				id = "boss_offer",
				speakerName = "Stan",
				text = "You're ready for the next big step. Let's visit the boss world. I'll show you where the portal is, then you'll take on your first boss and see how boss rewards work.",
				choices = {
					{
						id = "accept",
						text = "Show me bosses!",
						action = {
							type = "acceptQuest",
							nextNodeId = "boss_accepted",
							payload = {
								questId = "stan_boss_intro",
								providerId = "stan",
								readyNodeId = "boss_ready",
								style = "positive",
							},
						},
					},
					{
						id = "later",
						text = "I'll check it out soon.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			boss_accepted = {
				id = "boss_accepted",
				speakerName = "Stan",
				text = "Awesome. Head to the boss portal and use it to enter the boss world. Once you're in, defeat your first boss.",
				choices = {
					{
						id = "close",
						text = "On my way!",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			boss_reminder = {
				id = "boss_reminder",
				speakerName = "Stan",
				text = "You're close. Use the boss portal, then defeat your first boss.",
				choices = {
					{
						id = "close",
						text = "Got it.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			boss_ready = {
				id = "boss_ready",
				speakerName = "Stan",
				text = "That's a boss win! You found the portal, defeated your first boss, and saw how boss rewards work. Come grab your chest.",
				choices = {
					{
						id = "claim",
						text = "Thanks, Stan!",
						action = {
							type = "claimQuest",
							payload = {
								questId = "stan_boss_intro",
								providerId = "stan",
								closeDialogue = true,
								style = "positive",
							},
						},
					},
					{
						id = "later",
						text = "I'll grab it in a bit.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			appraisal_completed = {
				id = "appraisal_completed",
				speakerName = "Stan",
				text = "Great job. Appraisal is another way to squeeze more power out of parts you already like.",
				choices = {
					{
						id = "close",
						text = "Thanks!",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			crafting_completed = {
				id = "crafting_completed",
				speakerName = "Stan",
				text = "Great work. Crafting is where extra parts start turning into bigger goals.",
				choices = {
					{
						id = "close",
						text = "Thanks!",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
			completed = {
				id = "completed",
				speakerName = "Stan",
				text = "Great work. Bosses are a big step forward, and their rewards can help your build grow even faster.",
				choices = {
					{
						id = "close",
						text = "Thanks!",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
		},
	},
	merchant_default = {
		id = "merchant_default",
		rootNodeId = "intro",
		nodesById = {
			intro = {
				id = "intro",
				speakerName = "Merchant",
				text = "Need something? I've got a few shelves open if you're ready to browse.",
				choices = {
					{
						id = "shop",
						text = "Show me what you're selling.",
						action = {
							type = "openShopFrame",
							frameName = "ShopUI",
						},
					},
					{
						id = "leave",
						text = "Maybe later.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
		},
	},
	appraiser_default = {
		id = "appraiser_default",
		rootNodeId = "intro",
		nodesById = {
			intro = {
				id = "intro",
				speakerName = "Appraiser",
				text = "Bring me something worth judging and I'll take a proper look. Want to open the appraisal table?",
				choices = {
					{
						id = "appraise",
						text = "Open the appraisal table.",
						action = {
							type = "openFrame",
							frameName = "AppraisalUI",
							payload = {
								style = "positive",
								tutorialTargetId = "appraisalOpenChoice",
							},
						},
					},
					{
						id = "leave",
						text = "Maybe later.",
						action = {
							type = "closeDialogue",
						},
					},
				},
			},
		},
	},
}

definitionsById.stan_onboarding_paid_roll_intro = nil

local DialogueDefinitions = {}

function DialogueDefinitions.Get(dialogueId: string): DialogueDefinition?
	return definitionsById[dialogueId]
end

function DialogueDefinitions.GetAll(): { [string]: DialogueDefinition }
	return definitionsById
end

return table.freeze(DialogueDefinitions)
