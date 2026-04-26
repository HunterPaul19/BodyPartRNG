local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local configFolder = sharedFolder:WaitForChild("Config")
local LoggingConfig = require(configFolder:WaitForChild("LoggingConfig"))

local Logger = {}

local LOGGING_DISABLED_BANNER = [[
 ____            _             ____            _     ____  _   _  ____
| __ )  ___   __| |_   _      |  _ \ __ _ _ __| |_  |  _ \| \ | |/ ___|
|  _ \ / _ \ / _` | | | |_____| |_) / _` | '__| __| | |_) |  \| | |  _
| |_) | (_) | (_| | |_| |_____|  __/ (_| | |  | |_  |  _ <| |\  | |_| |
|____/ \___/ \__,_|\__, |     |_|   \__,_|_|   \__| |_| \_\_| \_|\____|
                   |___/
]]

local function isEnabled(): boolean
	return LoggingConfig.Enabled == true
end

if not isEnabled() then
	print(LOGGING_DISABLED_BANNER)
	print("If you find any bugs, please reach out so they can be fixed.")
end

function Logger.Print(...)
	if not isEnabled() then
		return
	end

	print(...)
end

function Logger.Warn(...)
	if not isEnabled() then
		return
	end

	warn(...)
end

function Logger.Error(message: any, level: number?)
	local errorLevel = 2
	if typeof(level) == "number" then
		errorLevel = if level == 0 then 0 else level + 1
	end

	error(message, errorLevel)
end

return table.freeze(Logger)
