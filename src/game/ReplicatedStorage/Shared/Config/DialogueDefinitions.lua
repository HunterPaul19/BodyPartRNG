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

export type DialogueDefinition = {
	id: string,
	rootNodeId: string,
	nodesById: { [string]: DialogueNode },
}

local definitionsById: { [string]: DialogueDefinition } = {
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

local DialogueDefinitions = {}

function DialogueDefinitions.Get(dialogueId: string): DialogueDefinition?
	return definitionsById[dialogueId]
end

function DialogueDefinitions.GetAll(): { [string]: DialogueDefinition }
	return definitionsById
end

return table.freeze(DialogueDefinitions)
