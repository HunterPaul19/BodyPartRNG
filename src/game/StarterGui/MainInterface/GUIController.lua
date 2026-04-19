local Players = game:GetService("Players")

return require(
	Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers"):WaitForChild("MainInterfaceController")
)
