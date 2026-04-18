local TweenService = game:GetService("TweenService")

local DEFAULT_FADE_IN_TIME = 0.18
local DEFAULT_HOLD_TIME = 1.0
local DEFAULT_FADE_OUT_TIME = 0.25

type TextGuiObject = TextLabel | TextButton | TextBox

type FadeTarget = {
	instance: Instance,
	property: string,
	value: number,
}

type PresentOptions = {
	message: string,
	messageLabelName: string?,
	fadeInTime: number?,
	holdTime: number?,
	fadeOutTime: number?,
	manageContainerVisibility: boolean?,
	onCreated: ((GuiObject, TextGuiObject?) -> ())?,
	warnPrefix: string?,
}

local activeEntriesByContainer = setmetatable({}, { __mode = "k" })
local nextLayoutOrderByContainer = setmetatable({}, { __mode = "k" })

local NotificationPresenter = {}

local function isTextGuiObject(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function findMessageLabel(root: GuiObject, messageLabelName: string?): TextGuiObject?
	if typeof(messageLabelName) == "string" and messageLabelName ~= "" then
		local namedDescendant = root:FindFirstChild(messageLabelName, true)
		if namedDescendant and isTextGuiObject(namedDescendant) then
			return namedDescendant :: TextGuiObject
		end
	end

	if isTextGuiObject(root) then
		return root :: TextGuiObject
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if isTextGuiObject(descendant) then
			return descendant :: TextGuiObject
		end
	end

	return nil
end

local function addFadeTarget(targets: { FadeTarget }, instance: Instance, property: string, value: number?)
	if typeof(value) ~= "number" then
		return
	end

	table.insert(targets, {
		instance = instance,
		property = property,
		value = value,
	})
end

local function collectFadeTargets(root: GuiObject): { FadeTarget }
	local targets = {}

	local function capture(instance: Instance)
		if instance:IsA("GuiObject") then
			addFadeTarget(targets, instance, "BackgroundTransparency", instance.BackgroundTransparency)
		end

		if isTextGuiObject(instance) then
			local textGui = instance :: TextGuiObject
			addFadeTarget(targets, textGui, "TextTransparency", textGui.TextTransparency)
			addFadeTarget(targets, textGui, "TextStrokeTransparency", textGui.TextStrokeTransparency)
		elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			addFadeTarget(targets, instance, "ImageTransparency", instance.ImageTransparency)
		elseif instance:IsA("UIStroke") then
			addFadeTarget(targets, instance, "Transparency", instance.Transparency)
		end
	end

	capture(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		capture(descendant)
	end

	return targets
end

local function setTargetsToHidden(targets: { FadeTarget })
	for _, target in ipairs(targets) do
		pcall(function()
			(target.instance :: any)[target.property] = 1
		end)
	end
end

local function playTweens(targets: { FadeTarget }, duration: number, hidden: boolean)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, target in ipairs(targets) do
		pcall(function()
			local targetValue = if hidden then 1 else target.value
			local tween = TweenService:Create(target.instance, tweenInfo, {
				[target.property] = targetValue,
			})
			tween:Play()
		end)
	end
end

local function setContainerVisible(container: GuiObject, isVisible: boolean)
	container.Visible = isVisible
end

local function incrementContainerEntryCount(container: GuiObject)
	activeEntriesByContainer[container] = (activeEntriesByContainer[container] or 0) + 1
	setContainerVisible(container, true)
end

local function decrementContainerEntryCount(container: GuiObject, manageContainerVisibility: boolean)
	local remainingEntries = math.max(0, (activeEntriesByContainer[container] or 1) - 1)
	if remainingEntries <= 0 then
		activeEntriesByContainer[container] = nil
		if manageContainerVisibility then
			setContainerVisible(container, false)
		end
		return
	end

	activeEntriesByContainer[container] = remainingEntries
end

function NotificationPresenter.Show(container: GuiObject, template: GuiObject, options: PresentOptions?): boolean
	if not (container and container:IsA("GuiObject")) then
		return false
	end

	if not (template and template:IsA("GuiObject")) then
		return false
	end

	options = options or {}

	local fadeInTime = math.max(0, tonumber(options.fadeInTime) or DEFAULT_FADE_IN_TIME)
	local holdTime = math.max(0, tonumber(options.holdTime) or DEFAULT_HOLD_TIME)
	local fadeOutTime = math.max(0, tonumber(options.fadeOutTime) or DEFAULT_FADE_OUT_TIME)
	local manageContainerVisibility = options.manageContainerVisibility ~= false
	local warnPrefix = if typeof(options.warnPrefix) == "string" and options.warnPrefix ~= ""
		then options.warnPrefix
		else "[NotificationPresenter]"

	template.Visible = false

	nextLayoutOrderByContainer[container] = (nextLayoutOrderByContainer[container] or 0) + 1
	local layoutOrder = nextLayoutOrderByContainer[container]

	local entry = template:Clone()
	entry.Name = string.format("%s_%d", template.Name, layoutOrder)
	entry.Visible = true
	entry.LayoutOrder = layoutOrder

	local messageLabel = findMessageLabel(entry, options.messageLabelName)
	if messageLabel then
		messageLabel.Text = tostring(options.message or "")
		messageLabel.Visible = true
	else
		warn(string.format("%s Missing message label under %s.", warnPrefix, entry:GetFullName()))
	end

	if typeof(options.onCreated) == "function" then
		options.onCreated(entry, messageLabel)
	end

	local fadeTargets = collectFadeTargets(entry)
	setTargetsToHidden(fadeTargets)

	entry.Parent = container
	incrementContainerEntryCount(container)
	playTweens(fadeTargets, fadeInTime, false)

	local didCleanup = false
	local function cleanup()
		if didCleanup then
			return
		end
		didCleanup = true

		if entry.Parent then
			entry:Destroy()
		end

		decrementContainerEntryCount(container, manageContainerVisibility)
	end

	task.delay(fadeInTime + holdTime, function()
		if entry.Parent then
			playTweens(fadeTargets, fadeOutTime, true)
		end

		task.delay(fadeOutTime, cleanup)
	end)

	return true
end

return NotificationPresenter
