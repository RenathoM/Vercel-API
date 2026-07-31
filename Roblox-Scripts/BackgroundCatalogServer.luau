--[[
	Server Script: BackgroundCatalogServer
	Location: ServerScriptService
	Purpose: Handles HTTP requests to the proxy API and returns
	background catalog data to the client via RemoteFunction.

	Architecture:
		- Client invokes GetBackgroundsRF with (keyword, limit)
		- Server formats the URL, makes the HTTP GET request
		- Server decodes JSON and returns the 'data' table
		- Errors are caught with pcall and returned gracefully
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")

-- Constants
local API_BASE_URL = "https://vercel-api-one-red.vercel.app/api/backgrounds"
local DEFAULT_KEYWORD = "background"
local DEFAULT_LIMIT = 28
local AVATAR_BACKGROUND_ASSET_TYPE_ID = 92
local BACKGROUND_TYPE_STRINGS = {
	"AvatarBackground",
	"Background",
	"background",
	"avatarbackground",
}

-- Error codes for catalog search failures
-- 021: Both search systems (HttpService + MarketplaceService/AvatarEditorService) failed
-- 022: External API returned no response (timeout / connection failure)
-- 023: MarketplaceService search outdated or returned invalid data
-- 024: Client RemoteFunction invocation failed (server unreachable)
-- 025: HttpService is disabled on the server
-- 026: API returned invalid/unexpected data format (JSON decode failure)
-- 027: Roblox catalog search (AvatarEditorService) failed
local ERROR_CODES = {
	BOTH_SYSTEMS_FAILED = "021",
	API_NO_RESPONSE = "022",
	MARKETPLACE_OUTDATED = "023",
	REMOTE_INVOCATION_FAILED = "024",
	HTTP_DISABLED = "025",
	API_INVALID_DATA = "026",
	ROBLOX_SEARCH_FAILED = "027",
}

local function isBackgroundAssetType(assetTypeValue)
	if type(assetTypeValue) == "string" then
		local lowerValue = string.lower(assetTypeValue)
		for _, bgStr in ipairs(BACKGROUND_TYPE_STRINGS) do
			if lowerValue == string.lower(bgStr) or string.find(lowerValue, "background") then
				return true
			end
		end
	elseif type(assetTypeValue) == "number" then
		return assetTypeValue == AVATAR_BACKGROUND_ASSET_TYPE_ID
	end
	return false
end

local function buildRobloxCatalogItem(item)
	return {
		AssetId = item.Id or 0,
		Name = item.Name or "No name",
		CreatorName = item.CreatorName or "Unknown",
		Price = item.Price or 0,
		ReleaseDate = item.ReleaseDate or item.Created or "---",
		Description = item.Description or "No description",
		ThumbnailUrl = string.format("rbxthumb://type=Asset&id=%d&w=420&h=420", item.Id or 0),
		AssetTypeId = item.AssetTypeId or AVATAR_BACKGROUND_ASSET_TYPE_ID,
	}
end

-- Retrieve the RemoteFunction
local getBackgroundsRF = ReplicatedStorage:FindFirstChild("GetBackgroundsRF")
if not getBackgroundsRF then
	warn("[BackgroundCatalogServer] GetBackgroundsRF not found in ReplicatedStorage!")
	return
end

--[[
	fetchBackgrounds(keyword: string, limit: number) -> {success: boolean, data: table?, error: string?}

	Builds the request URL with query parameters, performs the HTTP GET,
	decodes the JSON response, and returns the 'data' field.

	Parameters:
		keyword - Search term to filter backgrounds (URL-encoded automatically)
		limit   - Maximum number of results to return

	Returns:
		On success: {success = true, data = <decoded data table>}
		On failure: {success = false, error = <error message string>}
]]

-- Retry configuration
local MAX_RETRIES = 3
local RETRY_DELAY = 2 -- seconds between retries

local function fetchFromApi(keyword, limit)
	local encodedKeyword = HttpService:UrlEncode(keyword)
	local requestUrl = API_BASE_URL
		.. "?keyword=" .. encodedKeyword
		.. "&limit=" .. tostring(limit)

	local success, result
	for attempt = 1, MAX_RETRIES do
		success, result = pcall(function()
			return HttpService:GetAsync(requestUrl)
		end)

		if success then
			break
		end

		warn(string.format("[BackgroundCatalogServer] API request attempt %d/%d failed: %s", attempt, MAX_RETRIES, tostring(result)))
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY)
		end
	end

	if not success then
		return false, "API request failed after " .. MAX_RETRIES .. " attempts: " .. tostring(result), ERROR_CODES.API_NO_RESPONSE
	end

	local decodeSuccess, decoded = pcall(function()
		return HttpService:JSONDecode(result)
	end)

	if not decodeSuccess then
		return false, "API returned invalid JSON: " .. tostring(decoded), ERROR_CODES.API_INVALID_DATA
	end

	if type(decoded) == "table" then
		if decoded.success == false then
			return false, decoded.error or "API returned an error payload", ERROR_CODES.API_INVALID_DATA
		end
		if decoded.data ~= nil then
			return true, decoded.data
		end
		return true, decoded
	end

	return false, "API returned unexpected payload", ERROR_CODES.API_INVALID_DATA
end

local function fetchFromRoblox(keyword, limit)
	local searchParams = CatalogSearchParams.new()
	searchParams.SearchKeyword = keyword
	searchParams.SortType = Enum.CatalogSortType.Relevance
	searchParams.CategoryFilter = Enum.CatalogCategoryFilter.None
	searchParams.IncludeOffSale = false
	searchParams.Limit = limit

	local success, searchResult = pcall(function()
		return AvatarEditorService:SearchCatalogAsync(searchParams)
	end)

	if not success then
		warn("[BackgroundCatalogServer] SearchCatalogAsync failed: " .. tostring(searchResult))
		success, searchResult = pcall(function()
			return AvatarEditorService:SearchCatalog(searchParams)
		end)
	end

	if not success or not searchResult then
		return false, "Roblox search failed: " .. tostring(searchResult), ERROR_CODES.ROBLOX_SEARCH_FAILED
	end

	local items = {}
	pcall(function()
		items = searchResult:GetCurrentPage()
	end)

	local results = {}
	for _, item in ipairs(items) do
		if isBackgroundAssetType(item.AssetType or item.AssetTypeId) then
			table.insert(results, buildRobloxCatalogItem(item))
			if #results >= limit then
				break
			end
		end
	end

	return true, results
end

local function fetchBackgrounds(player, keyword, limit)
	keyword = tostring(keyword or DEFAULT_KEYWORD)
	if keyword == "" then
		keyword = DEFAULT_KEYWORD
	end
	limit = tonumber(limit) or DEFAULT_LIMIT

	if not HttpService.HttpEnabled then
		return {
			success = false,
			error = "HttpService is disabled on the server. Enable HttpService to use the remote catalog.",
			errorCode = ERROR_CODES.HTTP_DISABLED
		}
	end

	local apiSuccess, apiData, robloxSuccess, robloxData
	local apiDone, robloxDone = false, false
	local winnerSource
	local apiErrorCode, robloxErrorCode

	local function trySetWinner(source, success, result)
		if source == "api" then
			apiDone = true
			apiSuccess = success
			apiData = result
		elseif source == "roblox" then
			robloxDone = true
			robloxSuccess = success
			robloxData = result
		end
		if success and not winnerSource then
			winnerSource = source
		end
	end

	task.spawn(function()
		local success, result, code = fetchFromApi(keyword, limit)
		if code then apiErrorCode = code end
		trySetWinner("api", success, result)
	end)

	task.spawn(function()
		local success, result, code = fetchFromRoblox(keyword, limit)
		if code then robloxErrorCode = code end
		trySetWinner("roblox", success, result)
	end)

	local waited = 0
	while not winnerSource and not (apiDone and robloxDone) and waited < 15 do
		task.wait(0.1)
		waited = waited + 0.1
	end

	local chosenSource = winnerSource
	if not chosenSource then
		if apiDone and apiSuccess then
			chosenSource = "api"
		elseif robloxDone and robloxSuccess then
			chosenSource = "roblox"
		end
	end

	if chosenSource == "api" then
		print("[BackgroundCatalogServer] Using external API for catalog.")
		return {success = true, data = apiData}
	elseif chosenSource == "roblox" then
		print("[BackgroundCatalogServer] Using Roblox Background search for catalog.")
		return {success = true, data = robloxData}
	end

	local errorMessage = "No catalog source available."
	if apiDone and not apiSuccess then
		errorMessage = errorMessage .. " API: " .. tostring(apiData)
	end
	if robloxDone and not robloxSuccess then
		errorMessage = errorMessage .. " Roblox: " .. tostring(robloxData)
	end

	-- Determine the most specific error code
	-- If both systems failed, use 021 (both systems failed)
	-- Otherwise, use the specific error code from whichever system failed
	local finalErrorCode = ERROR_CODES.BOTH_SYSTEMS_FAILED
	if apiErrorCode and not robloxErrorCode then
		finalErrorCode = apiErrorCode
	elseif robloxErrorCode and not apiErrorCode then
		finalErrorCode = robloxErrorCode
	end

	return {
		success = false,
		error = errorMessage,
		errorCode = finalErrorCode,
		apiErrorCode = apiErrorCode,
		robloxErrorCode = robloxErrorCode,
	}
end

-- Connect the RemoteFunction to our handler
getBackgroundsRF.OnServerInvoke = fetchBackgrounds

print("[BackgroundCatalogServer] Ready. Listening for client requests via GetBackgroundsRF.")