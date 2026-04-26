local AdminActionRegistry = require(script.Parent.Parent.Admin.AdminActionRegistry)

local AdminPanelDefinitions = {}

AdminPanelDefinitions.Tabs = AdminActionRegistry.Tabs
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
				risk = action.risk,
				environment = action.environment,
				fields = action.fields,
				requiresConfirmation = action.requiresConfirmation,
				confirmationText = action.confirmationText,
			}
		end
	end
end

return AdminPanelDefinitions
