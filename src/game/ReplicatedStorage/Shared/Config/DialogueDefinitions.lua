export type DialogueAction = {
	type: "gotoNode" | "closeDialogue" | "openShopFrame",
	nextNodeId: string?,
	frameName: string?,
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
						id = "secret_stock",
						text = "What about the secret stock?",
						nextNodeId = "secret_stock",
						conditionIds = { "richEnoughForSecretStock" },
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
			secret_stock = {
				id = "secret_stock",
				speakerName = "Merchant",
				text = "Come back when you've got deeper pockets. I only show the secret shelf to serious collectors.",
				choices = {
					{
						id = "secret_back",
						text = "Back",
						nextNodeId = "intro",
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
