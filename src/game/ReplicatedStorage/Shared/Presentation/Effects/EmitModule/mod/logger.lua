local GlobalLogger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local function msg(...: string)
  return `[Forge Emit API]: {table.concat({ ... }, " ")}`
end

local logger = {}

function logger.error(...)
  GlobalLogger.Error(msg(..., "\n"))
end

function logger.warn(...)
  GlobalLogger.Warn(msg(...))
  GlobalLogger.Warn(msg(debug.traceback("stack trace:")))
end

function logger.info(...)
  GlobalLogger.Print(msg(...))
end

return logger
