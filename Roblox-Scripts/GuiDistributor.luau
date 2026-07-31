--!strict
-- GuiDistributor: Disabled server script.
-- BackgroundCatalogGui now lives in StarterGui, which is automatically
-- cloned to each player's PlayerGui by the Roblox engine.
-- This prevents duplicate GUI creation that occurred previously.

local Players = game:GetService("Players")

-- Ensure any duplicate GUIs (from previous GuiDistributor executions)
-- are removed from PlayerGui of already connected players.
local function cleanupDuplicateGuis(player: Player)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	local guis = playerGui:GetChildren()
	local catalogGuis = {}
	for _, child in ipairs(guis) do
		if child.Name == "BackgroundCatalogGui" then
			table.insert(catalogGuis, child)
		end
	end

	-- If there is more than one instance, remove extras (keep only the first)
	if #catalogGuis > 1 then
		for i = 2, #catalogGuis do
			catalogGuis[i].Parent = nil
		end
	end
end

Players.PlayerAdded:Connect(cleanupDuplicateGuis)

for _, player in Players:GetPlayers() do
	task.spawn(cleanupDuplicateGuis, player)
end