--[[
	BackgroundCatalogClient.luau
	Main client script that initializes the Background Catalog system.
	Reads the specifications from the Tarefa script and implements the full system.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local getBackgroundsRF = ReplicatedStorage:FindFirstChild("GetBackgroundsRF")

-- Wait for the local player
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for modules to load
local function waitForModule(path: string): ModuleScript
	local module = ReplicatedStorage:FindFirstChild(path, true)
	if module then return module end

	-- Try to find by full path
	local parts = path:split(".")
	local current: Instance = ReplicatedStorage
	for _, partName in parts do
		local found = current:FindFirstChild(partName)
		if found then
			current = found
		else
			return nil
		end
	end

	return if current:IsA("ModuleScript") then current else nil
end

-- Wait for the player's GUI
local function waitForPlayerGui(): ScreenGui
	local maxWait = 10
	local waited = 0
	while waited < maxWait do
		local gui = playerGui:FindFirstChild("BackgroundCatalogGui")
		if gui then return gui end
		task.wait(0.5)
		waited = waited + 0.5
	end
	return nil
end

--[[
	Error code descriptions for the popup system
]]
local ERROR_DESCRIPTIONS = {
	["021"] = "All catalog sources failed (API + AvatarEditorService)",
	["022"] = "External API returned no response (timeout / connection)",
	["024"] = "Server unreachable (RemoteFunction invocation failed)",
	["025"] = "HttpService is disabled on the server",
	["026"] = "API returned invalid/unexpected data format",
}

--[[
	Shows an error popup on screen with error code and automatically rejoins after 5 seconds.
	The timer appears on the right side of the popup.

	Parameters:
		errorCode (string?) - The error code to display (e.g. "021"). Defaults to "021" if not provided.
]]
local function showErrorAndRejoin(errorCode: string?)
	errorCode = errorCode or "021"
	local errorDesc = ERROR_DESCRIPTIONS[errorCode] or "Unknown error"

	local playerGui = player:WaitForChild("PlayerGui")

	-- Create popup ScreenGui
	local popupGui = Instance.new("ScreenGui")
	popupGui.Name = "ApiErrorPopup"
	popupGui.ResetOnSpawn = false
	popupGui.IgnoreGuiInset = true
	popupGui.DisplayOrder = 999
	popupGui.Parent = playerGui

	-- Dark backdrop covering the entire screen
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.6
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 100
	backdrop.Parent = popupGui

	-- Central dialog (wider to accommodate timer on the right)
	local dialog = Instance.new("Frame")
	dialog.Name = "Dialog"
	dialog.Size = UDim2.new(0, 500, 0, 200)
	dialog.Position = UDim2.new(0.5, -250, 0.5, -100)
	dialog.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	dialog.BorderSizePixel = 0
	dialog.ZIndex = 101
	dialog.Parent = popupGui

	local dialogCorner = Instance.new("UICorner")
	dialogCorner.CornerRadius = UDim.new(0, 12)
	dialogCorner.Parent = dialog

	local dialogStroke = Instance.new("UIStroke")
	dialogStroke.Color = Color3.fromRGB(215, 55, 55)
	dialogStroke.Thickness = 2
	dialogStroke.Parent = dialog

	-- Error icon
	local errorIcon = Instance.new("TextLabel")
	errorIcon.Size = UDim2.new(0.75, 0, 0, 50)
	errorIcon.Position = UDim2.new(0, 0, 0, 15)
	errorIcon.BackgroundTransparency = 1
	errorIcon.Text = "?"
	errorIcon.TextColor3 = Color3.fromRGB(215, 55, 55)
	errorIcon.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	errorIcon.TextSize = 36
	errorIcon.ZIndex = 102
	errorIcon.Parent = dialog

	-- Main error title: "System currently inoperative"
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.75, -10, 0, 30)
	title.Position = UDim2.new(0, 10, 0, 60)
	title.BackgroundTransparency = 1
	title.Text = "System currently inoperative"
	title.TextColor3 = Color3.fromRGB(240, 240, 250)
	title.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	title.TextSize = 18
	title.ZIndex = 102
	title.Parent = dialog

	-- Error code display: "error code [021]"
	local errorCodeLabel = Instance.new("TextLabel")
	errorCodeLabel.Size = UDim2.new(0.75, -10, 0, 25)
	errorCodeLabel.Position = UDim2.new(0, 10, 0, 90)
	errorCodeLabel.BackgroundTransparency = 1
	errorCodeLabel.Text = "error code [" .. errorCode .. "]"
	errorCodeLabel.TextColor3 = Color3.fromRGB(215, 55, 55)
	errorCodeLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	errorCodeLabel.TextSize = 16
	errorCodeLabel.ZIndex = 102
	errorCodeLabel.Parent = dialog

	-- Error description
	local message = Instance.new("TextLabel")
	message.Size = UDim2.new(0.75, -10, 0, 40)
	message.Position = UDim2.new(0, 10, 0, 115)
	message.BackgroundTransparency = 1
	message.Text = errorDesc
	message.TextColor3 = Color3.fromRGB(170, 170, 190)
	message.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
	message.TextSize = 12
	message.TextWrapped = true
	message.ZIndex = 102
	message.Parent = dialog

	-- Timer on the RIGHT side of the popup
	local timerContainer = Instance.new("Frame")
	timerContainer.Name = "TimerContainer"
	timerContainer.Size = UDim2.new(0, 100, 1, -20)
	timerContainer.Position = UDim2.new(1, -110, 0, 10)
	timerContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	timerContainer.BorderSizePixel = 0
	timerContainer.ZIndex = 103
	timerContainer.Parent = dialog

	local timerContainerCorner = Instance.new("UICorner")
	timerContainerCorner.CornerRadius = UDim.new(0, 10)
	timerContainerCorner.Parent = timerContainer

	local timerContainerStroke = Instance.new("UIStroke")
	timerContainerStroke.Color = Color3.fromRGB(255, 200, 100)
	timerContainerStroke.Thickness = 1.5
	timerContainerStroke.Parent = timerContainer

	-- Timer label inside the right container
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Size = UDim2.new(1, 0, 0.5, 0)
	timerLabel.Position = UDim2.new(0, 0, 0, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "5"
	timerLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
	timerLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	timerLabel.TextSize = 32
	timerLabel.ZIndex = 104
	timerLabel.Parent = timerContainer

	-- "seconds" label below the number
	local secondsLabel = Instance.new("TextLabel")
	secondsLabel.Size = UDim2.new(1, 0, 0.3, 0)
	secondsLabel.Position = UDim2.new(0, 0, 0.55, 0)
	secondsLabel.BackgroundTransparency = 1
	secondsLabel.Text = "seconds"
	secondsLabel.TextColor3 = Color3.fromRGB(200, 170, 100)
	secondsLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
	secondsLabel.TextSize = 11
	secondsLabel.ZIndex = 104
	secondsLabel.Parent = timerContainer

	-- Entrance animation
	dialog.BackgroundTransparency = 1
	local TWEEN_FAST = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(dialog, TWEEN_FAST, {BackgroundTransparency = 0}):Play()

	-- 5-second countdown with timer on the right
	task.spawn(function()
		for i = 5, 1, -1 do
			timerLabel.Text = tostring(i)
			task.wait(1)
		end
		timerLabel.Text = "0"
		secondsLabel.Text = "rejoining..."

		-- Automatic rejoin
		local placeId = game.PlaceId
		local jobId = game.JobId
		if jobId and jobId ~= "" then
			TeleportService:TeleportToPlaceInstance(placeId, jobId, player)
		else
			TeleportService:Teleport(placeId, player)
		end
	end)
end

local function invokeGetBackgrounds()
	if not getBackgroundsRF or not getBackgroundsRF:IsA("RemoteFunction") then
		warn("[BackgroundCatalog] GetBackgroundsRF not found or not a RemoteFunction.")
		return nil, "024"
	end

	local success, response = pcall(function()
		return getBackgroundsRF:InvokeServer()
	end)

	if not success then
		warn("[BackgroundCatalog] Failed to invoke GetBackgroundsRF:", response)
		return nil, "024"
	end

	if type(response) ~= "table" then
		warn("[BackgroundCatalog] Invalid response from server:", tostring(response))
		return nil, "024"
	end

	if not response.success then
		local errorCode = response.errorCode or "021"
		warn(string.format("[BackgroundCatalog] API error in response: %s (code: %s)", tostring(response.error), errorCode))
		return nil, errorCode
	end

	if type(response.data) ~= "table" then
		warn("[BackgroundCatalog] Server returned a non-table catalog payload.")
		return nil, "026"
	end

	return response.data, nil
end

-- Main initialization function
local function initialize()
	-- Aguardar a GUI ser copiada para o PlayerGui
	local gui = waitForPlayerGui()
	if not gui then
		warn("[BackgroundCatalog] GUI not found in PlayerGui")
		return
	end

	-- Show LoadingIndicator immediately, before any async operation
	local mainFrame = gui:FindFirstChild("MainFrame")
	if mainFrame then
		local earlyLoading = mainFrame:FindFirstChild("LoadingIndicator")
		if earlyLoading then
			earlyLoading.Visible = true
			earlyLoading.BackgroundTransparency = 0.4
		end
	end

	-- Load modules
	local catalogServiceModule = ReplicatedStorage:FindFirstChild("BackgroundCatalogSystem", true)
	if not catalogServiceModule then
		warn("[BackgroundCatalog] BackgroundCatalogSystem not found")
		return
	end

	local modulesFolder = ReplicatedStorage:FindFirstChild("BackgroundCatalogSystem")
	if not modulesFolder then
		warn("[BackgroundCatalog] Modules folder not found")
		return
	end

	local modules = modulesFolder:FindFirstChild("Modules")
	if not modules then
		warn("[BackgroundCatalog] Modules subfolder not found")
		return
	end

	-- Require modules
	local CatalogService = require(modules:FindFirstChild("CatalogService"))
	local ViewportRender = require(modules:FindFirstChild("ViewportRender"))
	local UIController = require(modules:FindFirstChild("UIController"))

	-- Get UI references
	local mainFrame = gui:FindFirstChild("MainFrame")
	local viewport = mainFrame and mainFrame:FindFirstChild("Center_3DViewport") :: ViewportFrame

	-- Initialize 3D renderer
	if viewport then
		ViewportRender.Initialize(viewport)
		ViewportRender.SetupAvatar(player)
	end

	-- Fetch catalog data from server (auto-discovers backgrounds via API + AvatarEditorService)
	local catalogData, errorCode = invokeGetBackgrounds()
	if catalogData then
		print(string.format("[BackgroundCatalog] Catalog received successfully. Items returned: %d", #catalogData))
	else
		warn("[BackgroundCatalog] Could not fetch catalog data from remote server. Error code: " .. tostring(errorCode))
		-- Show error popup with error code and auto-rejoin after 5 seconds
		showErrorAndRejoin(errorCode)
		return
	end

	-- Initialize UI controller and pass the received data
	UIController.Initialize(gui, catalogData)

	-- Support avatar rotation via drag on the viewport
	local isDragging = false
	local lastInputPosition = Vector3.zero

	if viewport then
		local function isPointInsideViewport(point: Vector3): boolean
			local vpPos = viewport.AbsolutePosition
			local vpSize = viewport.AbsoluteSize
			return point.X >= vpPos.X and point.X <= vpPos.X + vpSize.X
				and point.Y >= vpPos.Y and point.Y <= vpPos.Y + vpSize.Y
		end

		local function onInputBegan(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if isPointInsideViewport(input.Position) then
					isDragging = true
					lastInputPosition = input.Position
				end
			end
		end

		local function onInputChanged(input: InputObject)
			if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - lastInputPosition
				local rotationAngle = math.rad(delta.X * 0.5)
				ViewportRender.RotateAvatar(rotationAngle)
				lastInputPosition = input.Position
			end
		end

		local function onInputEnded(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				isDragging = false
			end
		end

		UserInputService.InputBegan:Connect(onInputBegan)
		UserInputService.InputChanged:Connect(onInputChanged)
		UserInputService.InputEnded:Connect(onInputEnded)
	end

	print("[BackgroundCatalog] System initialized successfully!")
end

-- Run initialization
initialize()
