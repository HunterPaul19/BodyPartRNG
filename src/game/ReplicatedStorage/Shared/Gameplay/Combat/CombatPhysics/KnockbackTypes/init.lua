local modules = {}

for _, child in ipairs(script:GetChildren()) do
	if child:IsA("ModuleScript") then
		modules[child.Name] = require(child)
	end
end

return modules
