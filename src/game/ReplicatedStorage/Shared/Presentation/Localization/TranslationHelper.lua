local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")

local LOCAL_PLAYER = Players.LocalPlayer
local TRANSLATOR_RETRY_COOLDOWN_SECONDS = 5

local TranslationHelper = {}

local cachedTranslator: Translator? = nil
local cachedLocaleId: string? = nil
local lastTranslatorAttemptAt = 0

local function getCurrentLocaleId(): string?
	if not LOCAL_PLAYER then
		return nil
	end

	local localeId = LOCAL_PLAYER.LocaleId
	if typeof(localeId) == "string" and localeId ~= "" then
		return localeId
	end

	return nil
end

local function resolveKeyAndFallback(entryOrKey: any, fallbackText: string?): (string?, string?)
	if typeof(entryOrKey) == "table" then
		local key = entryOrKey.key
		local fallback = entryOrKey.fallback
		local resolvedKey = if typeof(key) == "string" and key ~= "" then key else nil
		local resolvedFallback = if typeof(fallback) == "string" then fallback else fallbackText
		return resolvedKey, resolvedFallback
	end

	if typeof(entryOrKey) == "string" and entryOrKey ~= "" then
		return entryOrKey, fallbackText
	end

	return nil, fallbackText
end

local function formatFallbackTemplate(template: string?, arguments: any?): string
	if typeof(template) ~= "string" or template == "" then
		return ""
	end
	if typeof(arguments) ~= "table" then
		return template
	end

	return (string.gsub(template, "{([^}]+)}", function(token)
		local rawToken = tostring(token)
		local name = string.match(rawToken, "^([^:]+)")
		if not name or name == "" then
			return "{" .. rawToken .. "}"
		end

		if string.match(name, "^%d+$") then
			local indexedValue = arguments[tonumber(name)]
			if indexedValue == nil then
				return "{" .. rawToken .. "}"
			end

			return tostring(indexedValue)
		end

		local value = arguments[name]
		if value == nil then
			return "{" .. rawToken .. "}"
		end

		return tostring(value)
	end))
end

local function getTranslator(): Translator?
	if not LOCAL_PLAYER then
		return nil
	end

	local localeId = getCurrentLocaleId()
	if cachedTranslator ~= nil and cachedLocaleId == localeId then
		return cachedTranslator
	end

	local now = os.clock()
	if cachedTranslator == nil and cachedLocaleId == localeId and now - lastTranslatorAttemptAt < TRANSLATOR_RETRY_COOLDOWN_SECONDS then
		return nil
	end

	lastTranslatorAttemptAt = now
	cachedLocaleId = localeId

	local ok, translator = pcall(function()
		return LocalizationService:GetTranslatorForPlayerAsync(LOCAL_PLAYER)
	end)
	if ok and translator then
		cachedTranslator = translator
		return translator
	end

	cachedTranslator = nil
	return nil
end

local function setAutoLocalize(target: Instance, isEnabled: boolean)
	if target:IsA("GuiBase2d") then
		target.AutoLocalize = isEnabled
	elseif target:IsA("ProximityPrompt") then
		target.AutoLocalize = isEnabled
	end
end

function TranslationHelper.formatByKey(entryOrKey: any, arguments: any?, fallbackText: string?): string
	local key, fallback = resolveKeyAndFallback(entryOrKey, fallbackText)
	if key then
		local translator = getTranslator()
		if translator then
			local ok, translatedText = pcall(function()
				return translator:FormatByKey(key, arguments)
			end)
			if ok and typeof(translatedText) == "string" and translatedText ~= "" then
				return translatedText
			end
		end
	end

	return formatFallbackTemplate(fallback, arguments)
end

function TranslationHelper.translate(sourceText: string, context: Instance?): string
	if typeof(sourceText) ~= "string" or sourceText == "" then
		return ""
	end

	local translator = getTranslator()
	if translator then
		local ok, translatedText = pcall(function()
			return translator:Translate(context or game, sourceText)
		end)
		if ok and typeof(translatedText) == "string" and translatedText ~= "" then
			return translatedText
		end
	end

	return sourceText
end

function TranslationHelper.setLiteralText(target: Instance, text: string, propertyName: string?)
	local resolvedPropertyName = if typeof(propertyName) == "string" and propertyName ~= "" then propertyName else "Text"
	setAutoLocalize(target, false)
	local writableTarget = target :: any
	writableTarget[resolvedPropertyName] = text
end

function TranslationHelper.setSourceText(target: Instance, sourceText: string, propertyName: string?)
	local resolvedPropertyName = if typeof(propertyName) == "string" and propertyName ~= "" then propertyName else "Text"
	setAutoLocalize(target, true)
	local writableTarget = target :: any
	writableTarget[resolvedPropertyName] = sourceText
end

function TranslationHelper.setKeyText(target: Instance, entryOrKey: any, arguments: any?, propertyName: string?, fallbackText: string?)
	local resolvedText = TranslationHelper.formatByKey(entryOrKey, arguments, fallbackText)
	TranslationHelper.setLiteralText(target, resolvedText, propertyName)
end

return table.freeze(TranslationHelper)
