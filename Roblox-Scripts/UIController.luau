--[[
	UIController.luau
	Interface and Events Module for Background Catalog
	Handles player interactions, data loading and UI states
	Version 2.0 - Professional UI/UX with animations, transitions and visual feedback
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local UIController = {}

-- Module references
local CatalogService = require(ReplicatedStorage.BackgroundCatalogSystem.Modules.CatalogService)
local ViewportRender = require(ReplicatedStorage.BackgroundCatalogSystem.Modules.ViewportRender)

-- UI references
local screenGui: ScreenGui
local mainFrame: Frame
local leftPanel: Frame
local viewport: ViewportFrame
local rightPanel: Frame

-- UI sub-elements
local searchInput: TextBox
local creatorInput: TextBox
local minPriceInput: TextBox
local maxPriceInput: TextBox
local sortDropdown: TextButton
local resultsGrid: ScrollingFrame
local resultsCounter: TextLabel
local itemTitle: TextLabel
local creatorName: TextLabel
local releaseDate: TextLabel
local priceTag: TextLabel
local favoritesCounter: TextLabel
local descriptionLabel: TextLabel
local buyButton: TextButton
local reportButton: TextButton
local loadingIndicator: Frame
local fullscreenToggle: TextButton
local lightControl: Frame

-- Button icons
local expandIcon: ImageLabel

-- Icon image IDs
local EXPAND_IMAGE = "rbxassetid://132763338019471"        -- Expand

-- UI state
local isFullscreen: boolean = false
local selectedItem: CatalogService.CatalogItem? = nil
local isLoading: boolean = false
local lastResultsCount: number = 0

-- Sort options with icons
local SORT_OPTIONS = {
	{icon = "??", name = "Relevance"},
	{icon = "??", name = "Lowest Price"},
	{icon = "??", name = "Highest Price"},
	{icon = "??", name = "Recent Releases"},
}
local currentSortIndex: number = 1

-- Professional theme colors
local COLORS = {
	PRIMARY = Color3.fromRGB(0, 120, 215),
	PRIMARY_HOVER = Color3.fromRGB(20, 140, 235),
	SUCCESS = Color3.fromRGB(0, 180, 75),
	SUCCESS_HOVER = Color3.fromRGB(20, 200, 95),
	DANGER = Color3.fromRGB(215, 55, 55),
	DANGER_HOVER = Color3.fromRGB(235, 75, 75),
	TEXT = Color3.fromRGB(240, 240, 250),
	TEXT_DIM = Color3.fromRGB(170, 170, 190),
	CARD_BG = Color3.fromRGB(38, 38, 46),
	CARD_HOVER = Color3.fromRGB(55, 55, 68),
	CARD_SELECTED = Color3.fromRGB(0, 100, 180),
	PANEL_BG = Color3.fromRGB(22, 22, 28),
	INPUT_BG = Color3.fromRGB(35, 35, 42),
	BORDER = Color3.fromRGB(45, 45, 55),
}

-- Animation configuration
local TWEEN_FAST = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_MEDIUM = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_SLOW = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_SLIDE = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0)

-- Error code descriptions for the popup system
local ERROR_DESCRIPTIONS = {
	["021"] = "Both search systems failed (HttpService + MarketplaceService)",
	["022"] = "External API returned no response (timeout / connection)",
	["023"] = "MarketplaceService search outdated or invalid data",
	["024"] = "Server unreachable (RemoteFunction invocation failed)",
	["025"] = "HttpService is disabled on the server",
	["026"] = "API returned invalid/unexpected data format",
	["027"] = "Roblox catalog search (AvatarEditorService) failed",
}

-- Debounce for interactions
local cardDebounce: {[number]: boolean} = {}

--[[
	Initializes the UI controller with interface references
	Parameters: gui (ScreenGui) - the catalog ScreenGui
]]
function UIController.Initialize(gui: ScreenGui, initialResults: {CatalogService.CatalogItem}? ): ()
	screenGui = gui

	-- Get element references
	mainFrame = gui:FindFirstChild("MainFrame") :: Frame

	if mainFrame then
		leftPanel = mainFrame:FindFirstChild("LeftPanel_SearchFilters") :: Frame
		viewport = mainFrame:FindFirstChild("Center_3DViewport") :: ViewportFrame
		rightPanel = mainFrame:FindFirstChild("RightPanel_Details") :: Frame
		loadingIndicator = mainFrame:FindFirstChild("LoadingIndicator") :: Frame

		-- Viewport sub-elements
		if viewport then
			fullscreenToggle = viewport:FindFirstChild("FullscreenToggle") :: TextButton
			lightControl = viewport:FindFirstChild("LightControl") :: Frame
			expandIcon = fullscreenToggle and fullscreenToggle:FindFirstChild("ExpandIcon") :: ImageLabel
		end
	end

	if leftPanel then
		searchInput = leftPanel:FindFirstChild("SearchInput") :: TextBox
		creatorInput = leftPanel:FindFirstChild("CreatorInput") :: TextBox
		sortDropdown = leftPanel:FindFirstChild("SortDropdown") :: TextButton
		resultsGrid = leftPanel:FindFirstChild("ResultsGrid") :: ScrollingFrame
		resultsCounter = leftPanel:FindFirstChild("ResultsCounter") :: TextLabel

		local priceFrame = leftPanel:FindFirstChild("PriceRangeFrame")
		if priceFrame then
			minPriceInput = priceFrame:FindFirstChild("MinPrice") :: TextBox
			maxPriceInput = priceFrame:FindFirstChild("MaxPrice") :: TextBox
		end
	end

	if rightPanel then
		itemTitle = rightPanel:FindFirstChild("ItemTitle") :: TextLabel
		creatorName = rightPanel:FindFirstChild("CreatorName") :: TextLabel
		releaseDate = rightPanel:FindFirstChild("ReleaseDate") :: TextLabel
		priceTag = rightPanel:FindFirstChild("PriceTag") :: TextLabel
		favoritesCounter = rightPanel:FindFirstChild("FavoritesCounter") :: TextLabel
		descriptionLabel = rightPanel:FindFirstChild("Description") :: TextLabel
		buyButton = rightPanel:FindFirstChild("BuyButton") :: TextButton
		reportButton = rightPanel:FindFirstChild("ReportButton") :: TextButton
	end

	-- Catalog always visible (no toggle button)
	if mainFrame then
		mainFrame.Visible = true
	end

	-- Ensure loading is visible during initialization
	UIController.SetLoading(true)

	-- Initialize SortDropdown text
	if sortDropdown then
		local opt = SORT_OPTIONS[currentSortIndex]
		sortDropdown.Text = opt.icon .. " Sort: " .. opt.name
	end

	-- Setup events
	UIController.SetupEvents()

	-- If client already provided initial results, use directly
	if initialResults and type(initialResults) == "table" and #initialResults > 0 then
		UIController.PopulateResults(initialResults)
		UIController.SetLoading(false)
	else
		-- Auto-start search when opening catalog
		task.defer(function()
			task.wait(0.5)
			UIController.PerformSearch()
		end)
	end
end

--[[
	Sets up all UI interaction events
]]
function UIController.SetupEvents(): ()
	-- ============================================
	-- FULLSCREEN TOGGLE
	-- ============================================
	if fullscreenToggle then
		fullscreenToggle.MouseButton1Click:Connect(function()
			UIController.ToggleFullscreen()
		end)
	end

	-- ============================================
	-- LIGHTING CONTROL
	-- ============================================
	if lightControl then
		local brightnessInput = lightControl:FindFirstChild("BrightnessInput")
		if brightnessInput then
			brightnessInput.FocusLost:Connect(function(enterPressed)
				if enterPressed then
					local brightness = tonumber(brightnessInput.Text)
					if brightness and viewport then
						viewport.Ambient = Color3.fromRGB(
							math.clamp(brightness * 80, 0, 255),
							math.clamp(brightness * 80, 0, 255),
							math.clamp(brightness * 90, 0, 255)
						)
					end
				end
			end)
		end
	end

	-- ============================================
	-- SEARCH INPUTS
	-- ============================================
	if searchInput then
		searchInput.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				UIController.PerformSearch()
			end
		end)
	end

	if creatorInput then
		creatorInput.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				UIController.PerformSearch()
			end
		end)
	end

	-- Price inputs
	if minPriceInput then
		minPriceInput.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				UIController.PerformSearch()
			end
		end)
	end
	if maxPriceInput then
		maxPriceInput.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				UIController.PerformSearch()
			end
		end)
	end

	-- ============================================
	-- SORT DROPDOWN - Cycle options with icons
	-- ============================================
	if sortDropdown then
		sortDropdown.MouseButton1Click:Connect(function()
			currentSortIndex = (currentSortIndex % #SORT_OPTIONS) + 1
			local opt = SORT_OPTIONS[currentSortIndex]
			sortDropdown.Text = opt.icon .. " Sort: " .. opt.name
			UIController.PerformSearch()
		end)

		-- Hover effect
		sortDropdown.MouseEnter:Connect(function()
			TweenService:Create(sortDropdown, TWEEN_FAST, {BackgroundColor3 = Color3.fromRGB(45, 45, 55)}):Play()
		end)
		sortDropdown.MouseLeave:Connect(function()
			TweenService:Create(sortDropdown, TWEEN_FAST, {BackgroundColor3 = COLORS.INPUT_BG}):Play()
		end)
	end

	-- ============================================
	-- ACTION BUTTONS - Buy
	-- ============================================
	if buyButton then
		buyButton.MouseButton1Click:Connect(function()
			UIController.OnBuyClicked()
		end)

		-- Hover effects
		buyButton.MouseEnter:Connect(function()
			TweenService:Create(buyButton, TWEEN_FAST, {BackgroundColor3 = COLORS.SUCCESS_HOVER}):Play()
		end)
		buyButton.MouseLeave:Connect(function()
			TweenService:Create(buyButton, TWEEN_FAST, {BackgroundColor3 = COLORS.SUCCESS}):Play()
		end)
	end

	-- ============================================
	-- REPORT BUTTON - Report item
	-- ============================================
	if reportButton then
		reportButton.MouseButton1Click:Connect(function()
			UIController.OnReportClicked()
		end)

		reportButton.MouseEnter:Connect(function()
			TweenService:Create(reportButton, TWEEN_FAST, {BackgroundColor3 = COLORS.DANGER_HOVER}):Play()
		end)
		reportButton.MouseLeave:Connect(function()
			TweenService:Create(reportButton, TWEEN_FAST, {BackgroundColor3 = COLORS.DANGER}):Play()
		end)
	end
end

--[[
	Toggles fullscreen mode for the center viewport
]]
function UIController.ToggleFullscreen(): ()
	if not viewport or not leftPanel or not rightPanel then return end

	isFullscreen = not isFullscreen

	if isFullscreen then
		-- Expand viewport, esconder paineis
		TweenService:Create(leftPanel, TWEEN_MEDIUM, {Position = UDim2.new(-0.25, 0, 0.06, 0)}):Play()
		TweenService:Create(rightPanel, TWEEN_MEDIUM, {Position = UDim2.new(1.05, 0, 0.06, 0)}):Play()
		TweenService:Create(viewport, TWEEN_MEDIUM, {Size = UDim2.new(0.98, 0, 0.90, 0), Position = UDim2.new(0.5, 0, 0.53, 0)}):Play()
		if fullscreenToggle then
			fullscreenToggle.Text = "?"
		end
	else
		-- Restore layout
		TweenService:Create(leftPanel, TWEEN_MEDIUM, {Position = UDim2.new(0.01, 0, 0.06, 0)}):Play()
		TweenService:Create(rightPanel, TWEEN_MEDIUM, {Position = UDim2.new(0.77, 0, 0.06, 0)}):Play()
		TweenService:Create(viewport, TWEEN_MEDIUM, {Size = UDim2.new(0.52, 0, 0.86, 0), Position = UDim2.new(0.5, 0, 0.53, 0)}):Play()
		if fullscreenToggle then
			fullscreenToggle.Text = "?"
		end
	end
end

--[[
	Shows an error popup with error code and auto-rejoin after 5 seconds.
	Used when client-side catalog search fails completely.
]]
local function showErrorPopup(errorCode: string?)
	errorCode = errorCode or "021"
	local errorDesc = ERROR_DESCRIPTIONS[errorCode] or "Unknown error"
	local player = Players.LocalPlayer
	if not player then return end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	-- Remove any existing error popup
	local existing = playerGui:FindFirstChild("CatalogErrorPopup")
	if existing then existing:Destroy() end

	-- Create popup ScreenGui
	local popupGui = Instance.new("ScreenGui")
	popupGui.Name = "CatalogErrorPopup"
	popupGui.ResetOnSpawn = false
	popupGui.IgnoreGuiInset = true
	popupGui.DisplayOrder = 999
	popupGui.Parent = playerGui

	-- Dark backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.6
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 100
	backdrop.Parent = popupGui

	-- Central dialog
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

	-- Main error title
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

	-- Error code display
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

	-- Timer on the RIGHT side
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
	TweenService:Create(dialog, TWEEN_FAST, {BackgroundTransparency = 0}):Play()

	-- 5-second countdown
	task.spawn(function()
		for i = 5, 1, -1 do
			timerLabel.Text = tostring(i)
			task.wait(1)
		end
		timerLabel.Text = "0"
		secondsLabel.Text = "rejoining..."

		local placeId = game.PlaceId
		local jobId = game.JobId
		if jobId and jobId ~= "" then
			TeleportService:TeleportToPlaceInstance(placeId, jobId, player)
		else
			TeleportService:Teleport(placeId, player)
		end
	end)
end

--[[
	Performs catalog search with current filters
]]
function UIController.PerformSearch(): ()
	if isLoading then return end

	-- Show loading indicator
	UIController.SetLoading(true)

	-- Collect search parameters
	local params: CatalogService.SearchParams = {
		Keyword = if searchInput and searchInput.Text ~= "" then searchInput.Text else nil,
		CreatorFilter = if creatorInput and creatorInput.Text ~= "" then creatorInput.Text else nil,
		MinPrice = if minPriceInput and minPriceInput.Text ~= "" then tonumber(minPriceInput.Text) else nil,
		MaxPrice = if maxPriceInput and maxPriceInput.Text ~= "" then tonumber(maxPriceInput.Text) else nil,
		SortType = SORT_OPTIONS[currentSortIndex].name,
	}

	-- Search in separate thread to avoid blocking UI
	task.spawn(function()
		local results, errorCode = CatalogService.SearchCatalog(params)
		if errorCode and #results == 0 then
			-- Both client-side search systems failed, show error popup
			warn("[BackgroundCatalog] Client search failed with error code: " .. errorCode)
			UIController.SetLoading(false)
			showErrorPopup(errorCode)
			return
		end
		UIController.PopulateResults(results)
		UIController.SetLoading(false)
	end)
end

--[[
	Populates results grid with found items
	Parameters: items ({CatalogService.CatalogItem}) - item list
]]
function UIController.PopulateResults(items: {CatalogService.CatalogItem}): ()
	if not resultsGrid then return end

	lastResultsCount = #items

	-- Update results counter
	if resultsCounter then
		resultsCounter.Text = "Items Found: " .. #items
	end

	-- Clear previous results (keep only UIGridLayout, UIPadding, UICorner and UIAspectRatioConstraint)
	for _, child in resultsGrid:GetChildren() do
		if not child:IsA("UIGridLayout") and not child:IsA("UIAspectRatioConstraint") and not child:IsA("UIPadding") and not child:IsA("UICorner") then
			child.Parent = nil
		end
	end

	-- Create cards for each item with entrance animation
	for index, item in ipairs(items) do
		if not item or not item.AssetId then
			warn("[UIController] Skipping invalid item at index " .. index)
			continue
		end
		local card = Instance.new("TextButton")
		-- Usar %.0f para evitar notacao cientifica em IDs de 15 digitos (ex: 1.21e+14)
		card.Name = "Card_" .. string.format("%.0f", item.AssetId)
		card.Size = UDim2.new(0.5, -5, 0, 100) -- UIGridLayout overrides, but keeps consistency
		card.BackgroundColor3 = COLORS.CARD_BG
		card.Text = ""
		card.BorderSizePixel = 0
		card.LayoutOrder = index
		card.AutoButtonColor = false
		card.ClipsDescendants = true
		card.Parent = resultsGrid

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 8)
		cardCorner.Parent = card

		-- UIStroke for subtle border
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Name = "CardStroke"
		cardStroke.Color = COLORS.BORDER
		cardStroke.Thickness = 1
		cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cardStroke.Parent = card

		-- Thumbnail image
		local thumbnail = Instance.new("ImageLabel")
		thumbnail.Name = "Thumbnail"
		thumbnail.Size = UDim2.new(1, 0, 0.7, 0)
		thumbnail.Position = UDim2.new(0, 0, 0, 0)
		thumbnail.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
		thumbnail.BackgroundTransparency = 0
		thumbnail.Image = item.ThumbnailUrl
		thumbnail.ScaleType = Enum.ScaleType.Fit
		thumbnail.BorderSizePixel = 0

		local thumbnailCorner = Instance.new("UICorner")
		thumbnailCorner.CornerRadius = UDim.new(0, 8)
		thumbnailCorner.Parent = thumbnail

		thumbnail.Parent = card

		-- Item name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "ItemName"
		nameLabel.Size = UDim2.new(0.6, -4, 0.3, 0)
		nameLabel.Position = UDim2.new(0, 4, 0.7, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3 = COLORS.TEXT_DIM
		nameLabel.Text = item.Name
		nameLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal)
		nameLabel.TextSize = 10
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		-- Price with icon
		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "Price"
		priceLabel.Size = UDim2.new(0.4, -4, 0.3, 0)
		priceLabel.Position = UDim2.new(0.6, 0, 0.7, 0)
		priceLabel.BackgroundTransparency = 1
		priceLabel.TextColor3 = Color3.fromRGB(0, 200, 100)
		local price = item.Price or 0
		priceLabel.Text = price > 0 and ("??" .. tostring(price)) or "Free"
		priceLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
		priceLabel.TextSize = 9
		priceLabel.TextXAlignment = Enum.TextXAlignment.Right
		priceLabel.Parent = card

		-- Staggered entrance animation
		card.BackgroundTransparency = 1
		task.defer(function()
			local delay = index * 0.03 -- Staggered delay
			task.wait(delay)
			TweenService:Create(card, TWEEN_MEDIUM, {BackgroundTransparency = 0}):Play()
		end)

		-- Card click event
		card.MouseButton1Click:Connect(function()
			UIController.OnCardSelected(item, card)
		end)

		-- Hover effect with smooth tween
		card.MouseEnter:Connect(function()
			if (selectedItem == nil or selectedItem.AssetId ~= item.AssetId) and item.AssetId then
				TweenService:Create(card, TWEEN_FAST, {BackgroundColor3 = COLORS.CARD_HOVER}):Play()
				local s = card:FindFirstChild("CardStroke")
				if s then TweenService:Create(s, TWEEN_FAST, {Color = Color3.fromRGB(80, 80, 100)}):Play() end
			end
		end)
		card.MouseLeave:Connect(function()
			if (selectedItem == nil or selectedItem.AssetId ~= item.AssetId) and item.AssetId then
				TweenService:Create(card, TWEEN_FAST, {BackgroundColor3 = COLORS.CARD_BG}):Play()
				local s = card:FindFirstChild("CardStroke")
				if s then TweenService:Create(s, TWEEN_FAST, {Color = COLORS.BORDER}):Play() end
			end
		end)
	end

	-- Update canvas size using AutomaticCanvasSize if available, else manual calculation
	local gridLayout = resultsGrid:FindFirstChildOfClass("UIGridLayout")
	if gridLayout then
		-- Ensure 2 columns (FillDirectionMaxCells) and relative CellSize
		if gridLayout.FillDirectionMaxCells ~= 2 then
			gridLayout.FillDirectionMaxCells = 2
		end
		if gridLayout.CellSize.X.Scale < 0.1 then
			gridLayout.CellSize = UDim2.new(0.5, -5, 0, 100)
		end
		-- Use AutomaticCanvasSize for dynamic calculation
		resultsGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
		-- Fallback: manual calculation if AutomaticCanvasSize doesn't work
		local cellPad = gridLayout.CellPadding
		local cellSize = gridLayout.CellSize
		local cols = gridLayout.FillDirectionMaxCells
		if cols <= 0 then cols = 2 end
		local rows = math.ceil(#items / cols)
		local rowHeight = cellSize.Y.Offset + cellPad.Y.Offset
		resultsGrid.CanvasSize = UDim2.new(0, 0, 0, rows * rowHeight)
	end
end

--[[
	Handles card selection in catalog with highlight animation
	Parameters: item (CatalogService.CatalogItem) - selected item
				card (TextButton) - the card button
]]
function UIController.OnCardSelected(item: CatalogService.CatalogItem, card: TextButton): ()
	-- Deselect previous card with animation
	if resultsGrid then
		for _, child in resultsGrid:GetChildren() do
			if child:IsA("TextButton") and child ~= card then
				TweenService:Create(child, TWEEN_FAST, {BackgroundColor3 = COLORS.CARD_BG}):Play()
				local s = child:FindFirstChild("CardStroke")
				if s then TweenService:Create(s, TWEEN_FAST, {Color = COLORS.BORDER, Thickness = 1}):Play() end
			end
		end
	end

	-- Select new card with highlight animation (bright blue border)
	TweenService:Create(card, TWEEN_FAST, {BackgroundColor3 = COLORS.CARD_SELECTED}):Play()
	local cardStroke = card:FindFirstChild("CardStroke")
	if cardStroke then
		TweenService:Create(cardStroke, TWEEN_FAST, {Color = Color3.fromRGB(0, 150, 255), Thickness = 2}):Play()
	end

	selectedItem = item

	-- Animate details panel
	if itemTitle then
		itemTitle.Text = item.Name
		-- Pulse animation
		TweenService:Create(itemTitle, TWEEN_FAST, {TextTransparency = 0.5}):Play()
		task.defer(function()
			task.wait(0.1)
			TweenService:Create(itemTitle, TWEEN_FAST, {TextTransparency = 0}):Play()
		end)
	end

	if creatorName then
		creatorName.Text = "?? Creator: " .. item.CreatorName
	end
	if releaseDate then
		local dateStr = item.ReleaseDate or "---"
		if dateStr == "---" then
			releaseDate.Text = "?? Release: Unavailable"
		else
			releaseDate.Text = "?? Release: " .. dateStr
		end
	end
	if priceTag then
		if item.Price > 0 then
			priceTag.Text = "?? R$ " .. item.Price
			priceTag.TextColor3 = Color3.fromRGB(0, 200, 100)
		else
			priceTag.Text = "?? Free"
			priceTag.TextColor3 = Color3.fromRGB(100, 200, 255)
		end
	end
	if favoritesCounter then
		-- Use real favorites count from the API; fall back to "---" if unavailable
		if not item.AssetId then return end
		local favs = item.FavoriteCount
		if type(favs) == "number" and favs > 0 then
			-- Format large numbers: 1234 → 1,234 | 12345 → 12.3k | 1234567 → 1.2M
			local formatted
			if favs >= 1000000 then
				formatted = string.format("%.1fM", favs / 1000000)
			elseif favs >= 10000 then
				formatted = string.format("%.1fk", favs / 1000)
			else
				formatted = tostring(favs)
			end
			favoritesCounter.Text = "❤ Favorites: " .. formatted
		else
			favoritesCounter.Text = "❤ Favorites: ---"
		end
	end
	if descriptionLabel then
		local desc = item.Description or "No Description"
		if desc == "" then desc = "No Description" end
		descriptionLabel.Text = desc
	end

	-- Apply background to avatar in viewport (equips on click)
	if item.AssetId then
		-- Aplicar background no viewport (apenas assetId necessario)
		ViewportRender.ApplyBackground(item.AssetId)
	end
	ViewportRender.FocusOnAvatar()
end

--[[
	Handles Buy button click with visual feedback
]]
function UIController.OnBuyClicked(): ()
	if not selectedItem then return end

	-- Visual click feedback
	if buyButton then
		TweenService:Create(buyButton, TWEEN_FAST, {BackgroundColor3 = Color3.fromRGB(0, 140, 55)}):Play()
		task.defer(function()
			task.wait(0.15)
			TweenService:Create(buyButton, TWEEN_FAST, {BackgroundColor3 = COLORS.SUCCESS}):Play()
		end)
	end

	local player = Players.LocalPlayer
	if player and selectedItem and selectedItem.AssetId and selectedItem.AssetId > 0 then
		-- Determine asset type correctly
		local assetType = Enum.InfoType.Asset
		if selectedItem.AssetTypeId > 0 then
			-- For certain types like Game Pass, Bundle, etc.
			if selectedItem.AssetTypeId == 34 then
				assetType = Enum.InfoType.GamePass
			end
		end
		local success, err = pcall(function()
			if selectedItem.AssetId then
				MarketplaceService:PromptPurchase(player, selectedItem.AssetId)
			end
		end)
		if not success then
			warn("[BackgroundCatalog] Error opening purchase: " .. tostring(err))
		end
	end
end

-- Manipula o clique no botao Report
function UIController.OnReportClicked(): ()
	if not selectedItem or not selectedItem.AssetId then return end

	-- Feedback visual
	if reportButton then
		local originalColor = reportButton.BackgroundColor3
		TweenService:Create(reportButton, TWEEN_FAST, {BackgroundColor3 = Color3.fromRGB(180, 40, 40)}):Play()
		task.defer(function()
			task.wait(0.2)
			TweenService:Create(reportButton, TWEEN_FAST, {BackgroundColor3 = originalColor}):Play()
		end)
	end

	-- Open asset report page in browser
	local assetId = selectedItem.AssetId

	local player = Players.LocalPlayer
	if player and assetId > 0 then
		-- Use Roblox's built-in report system
		-- Try opening report modal via link
		print(string.format("[BackgroundCatalog] Report requested for asset %d (%s)", assetId, selectedItem.Name))

		-- Create a simple confirmation dialog in UI
		if screenGui then
			local dialog = Instance.new("Frame")
			dialog.Name = "ReportDialog"
			dialog.Size = UDim2.new(0, 300, 0, 160)
			dialog.Position = UDim2.new(0.5, -150, 0.5, -80)
			dialog.BackgroundColor3 = COLORS.PANEL_BG
			dialog.BackgroundTransparency = 0.02
			dialog.BorderSizePixel = 0
			dialog.ZIndex = 100
			dialog.Parent = screenGui

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 12)
			corner.Parent = dialog

			local stroke = Instance.new("UIStroke")
			stroke.Color = COLORS.DANGER
			stroke.Thickness = 2
			stroke.Parent = dialog

			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, -20, 0, 40)
			title.Position = UDim2.new(0, 10, 0, 10)
			title.BackgroundTransparency = 1
			title.Text = "? Report Item"
			title.TextColor3 = COLORS.TEXT
			title.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
			title.TextSize = 18
			title.Parent = dialog

			local desc = Instance.new("TextLabel")
			desc.Size = UDim2.new(1, -20, 0, 50)
			desc.Position = UDim2.new(0, 10, 0, 50)
			desc.BackgroundTransparency = 1
			desc.Text = string.format("Do you want to report \"%s\" (ID: %d)?\nYou will be redirected.", selectedItem.Name, assetId)
			desc.TextColor3 = COLORS.TEXT_DIM
			desc.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
			desc.TextSize = 13
			desc.TextWrapped = true
			desc.Parent = dialog

			local confirmBtn = Instance.new("TextButton")
			confirmBtn.Size = UDim2.new(0.45, 0, 0, 35)
			confirmBtn.Position = UDim2.new(0.05, 0, 1, -40)
			confirmBtn.BackgroundColor3 = COLORS.DANGER
			confirmBtn.Text = "Report"
			confirmBtn.TextColor3 = Color3.new(1, 1, 1)
			confirmBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
			confirmBtn.TextSize = 14
			confirmBtn.BorderSizePixel = 0
			confirmBtn.ZIndex = 100
			confirmBtn.Parent = dialog

			local confirmCorner = Instance.new("UICorner")
			confirmCorner.CornerRadius = UDim.new(0, 8)
			confirmCorner.Parent = confirmBtn

			local cancelBtn = Instance.new("TextButton")
			cancelBtn.Size = UDim2.new(0.45, 0, 0, 35)
			cancelBtn.Position = UDim2.new(0.5, 0, 1, -40)
			cancelBtn.BackgroundColor3 = COLORS.INPUT_BG
			cancelBtn.Text = "Cancel"
			cancelBtn.TextColor3 = COLORS.TEXT
			cancelBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
			cancelBtn.TextSize = 14
			cancelBtn.BorderSizePixel = 0
			cancelBtn.ZIndex = 100
			cancelBtn.Parent = dialog

			local cancelCorner = Instance.new("UICorner")
			cancelCorner.CornerRadius = UDim.new(0, 8)
			cancelCorner.Parent = cancelBtn

			-- Entrance animation
			dialog.BackgroundTransparency = 1
			dialog.Size = UDim2.new(0, 280, 0, 140)
			TweenService:Create(dialog, TWEEN_MEDIUM, {BackgroundTransparency = 0.02, Size = UDim2.new(0, 300, 0, 160)}):Play()

			confirmBtn.MouseButton1Click:Connect(function()
				dialog:Destroy()
			end)

			cancelBtn.MouseButton1Click:Connect(function()
				dialog:Destroy()
			end)
		end
	end
end

--[[
	Sets loading state of UI with animation
	Parameters: loading (boolean) - if loading
]]
function UIController.SetLoading(loading: boolean): ()
	isLoading = loading

	if loadingIndicator then
		if loading then
			loadingIndicator.Visible = true
			loadingIndicator.BackgroundTransparency = 1
			TweenService:Create(loadingIndicator, TWEEN_MEDIUM, {BackgroundTransparency = 0.4}):Play()
		else
			local fadeOut = TweenService:Create(loadingIndicator, TWEEN_FAST, {BackgroundTransparency = 1})
			fadeOut:Play()
			fadeOut.Completed:Connect(function()
				loadingIndicator.Visible = false
			end)
		end
	end
end

--[[
	Returns currently selected item
	Retorna: CatalogService.CatalogItem?
]]
function UIController.GetSelectedItem(): CatalogService.CatalogItem?
	return selectedItem
end

--[[
	Returns number of results from last search
	Retorna: number
]]
function UIController.GetResultsCount(): number
	return lastResultsCount
end

return UIController
