--[[
	CatalogService.luau
	Modulo de Consulta ao Catalogo de Planos de Fundo
	Utiliza AvatarEditorService e CatalogSearchParams para buscar itens do Marketplace
	CORRIGIDO: Usa GetBatchItemDetailsAsync e SearchCatalogAsync corretamente
]]

local AvatarEditorService = game:GetService("AvatarEditorService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

-- Error codes for client-side catalog search failures
-- These mirror the server error codes for consistency
local ERROR_CODES = {
	BOTH_SYSTEMS_FAILED = "021",     -- Both search systems failed
	API_NO_RESPONSE = "022",        -- External API no response (server-side only)
	MARKETPLACE_OUTDATED = "023",   -- MarketplaceService search outdated or invalid data
	REMOTE_INVOCATION_FAILED = "024", -- Server unreachable
	HTTP_DISABLED = "025",          -- HttpService disabled (server-side only)
	API_INVALID_DATA = "026",       -- API invalid data (server-side only)
	ROBLOX_SEARCH_FAILED = "027",   -- Roblox catalog search (AvatarEditorService) failed
}

local CatalogService = {}

-- Tipo para os itens do catalogo
export type CatalogItem = {
	AssetId: number,
	Name: string,
	CreatorName: string,
	Price: number,
	ReleaseDate: string,
	Description: string,
	ThumbnailUrl: string,
	AssetTypeId: number,
}

-- Tipo para os parametros de busca
export type SearchParams = {
	Keyword: string?,
	CreatorFilter: string?,
	MinPrice: number?,
	MaxPrice: number?,
	SortType: string?,
}

-- Mapeamento de tipos de ordenacao
local SORT_MAP: {[string]: Enum.CatalogSortType} = {
	["Relevância"] = Enum.CatalogSortType.Relevance,
	["Menor Preço"] = Enum.CatalogSortType.PriceLowToHigh,
	["Maior Preço"] = Enum.CatalogSortType.PriceHighToLow,
	["Lançamentos Recentes"] = Enum.CatalogSortType.RecentlyCreated,
	["Mais Favoritos"] = Enum.CatalogSortType.MostFavorited,
	["Mais Vendidos"] = Enum.CatalogSortType.Bestselling,
	-- Compatibilidade com nomes sem acento
	["Relevancia"] = Enum.CatalogSortType.Relevance,
	["Menor Preco"] = Enum.CatalogSortType.PriceLowToHigh,
	["Maior Preco"] = Enum.CatalogSortType.PriceHighToLow,
	["Lancamentos Recentes"] = Enum.CatalogSortType.RecentlyCreated,
}

-- IDs de itens de background do marketplace (aba Plano de Fundo)
-- Estes sao IDs do catalogo que funcionam com AvatarEditorService:GetItemDetailsAsync
local FEATURED_BACKGROUND_IDS = {
	121199209890990,
	116956243809295,
	139579276427743,
	132272208178794,
	105589844216517, -- Exemplo adicional de background
	92496597846544,  -- Background adicional
	132763338019471, -- Background adicional
	104678130498114, -- Background adicional
}

-- Tipo de asset para fundos de perfil (AvatarBackground = AssetTypeId 92)
-- Nota: 92 nao esta no enum publico AssetType mas e retornado pela API
local AVATAR_BACKGROUND_ASSET_TYPE_ID = 92

-- Strings que podem aparecer no campo AssetType para backgrounds
local BACKGROUND_TYPE_STRINGS = {
	"AvatarBackground",
	"Background",
	"background",
	"avatarbackground",
}

-- Verifica se uma string de tipo de asset corresponde a um background
local function isBackgroundAssetType(assetTypeValue): boolean
	if type(assetTypeValue) == "string" then
		for _, bgStr in ipairs(BACKGROUND_TYPE_STRINGS) do
			if string.lower(assetTypeValue) == string.lower(bgStr) then
				return true
			end
		end
		-- Tambem checar se contem "background"
		if string.find(string.lower(assetTypeValue), "background") then
			return true
		end
	elseif type(assetTypeValue) == "number" then
		return assetTypeValue == AVATAR_BACKGROUND_ASSET_TYPE_ID
	end
	return false
end

-- Cache de itens buscados
local itemCache: {CatalogItem} = {}
local lastSearchParams: SearchParams = {}

--[[
	Busca informacoes de itens de background via IDs especificos
	Usa AvatarEditorService:GetBatchItemDetailsAsync (mais eficiente) ou
	AvatarEditorService:GetItemDetailsAsync como fallback.
	Estes IDs sao do novo formato do catalogo (14-15 digitos) e NAO funcionam
	com MarketplaceService:GetProductInfo.
	Retorna: {CatalogItem} - lista de itens formatados
]]
local function fetchFeaturedBackgrounds(): {CatalogItem}
	local results: {CatalogItem} = {}

	-- Tentar GetBatchItemDetailsAsync primeiro (mais eficiente)
	local batchSuccess, batchResults = pcall(function()
		return AvatarEditorService:GetBatchItemDetailsAsync(FEATURED_BACKGROUND_IDS, Enum.AvatarItemType.Asset)
	end)

	if batchSuccess and type(batchResults) == "table" then
		for _, item in ipairs(batchResults) do
			local assetId = item.Id or 0
			if assetId > 0 then
				local catalogItem: CatalogItem = {
					AssetId = assetId,
					Name = item.Name or "No name",
					CreatorName = item.CreatorName or "Unknown",
					Price = item.Price or 0,
					ReleaseDate = "---",
					Description = item.Description or "No description",
					ThumbnailUrl = string.format("rbxthumb://type=Asset&id=%d&w=420&h=420", assetId),
					AssetTypeId = AVATAR_BACKGROUND_ASSET_TYPE_ID,
				}
				table.insert(results, catalogItem)
			end
		end
		print(string.format("[BackgroundCatalog] BatchItemDetails retornou %d itens", #results))
		return results
	end

	-- Fallback: buscar um por um via GetItemDetailsAsync
	print("[BackgroundCatalog] Batch falhou, tentando GetItemDetailsAsync individualmente...")
	for _, assetId in ipairs(FEATURED_BACKGROUND_IDS) do
		local success, item = pcall(function()
			return AvatarEditorService:GetItemDetailsAsync(assetId, Enum.AvatarItemType.Asset)
		end)

		if success and item then
			local catalogItem: CatalogItem = {
				AssetId = assetId,
				Name = item.Name or "No name",
				CreatorName = item.CreatorName or "Unknown",
				Price = item.Price or 0,
				ReleaseDate = item.ReleaseDate or item.Created or "---",
				Description = item.Description or "No description",
				ThumbnailUrl = string.format("rbxthumb://type=Asset&id=%d&w=420&h=420", assetId),
				AssetTypeId = AVATAR_BACKGROUND_ASSET_TYPE_ID,
			}
			table.insert(results, catalogItem)
		else
			-- Ultimo fallback: tentar MarketplaceService:GetProductInfo
			local mpSuccess, info = pcall(function()
				return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
			end)
			if mpSuccess and info then
				local catalogItem: CatalogItem = {
					AssetId = assetId,
					Name = info.Name or "No name",
					CreatorName = (info.Creator and info.Creator.Name) or "Unknown",
					Price = info.PriceInRobux or 0,
					ReleaseDate = info.Created or "---",
					Description = info.Description or "No description",
					ThumbnailUrl = string.format("rbxthumb://type=Asset&id=%d&w=420&h=420", assetId),
					AssetTypeId = info.AssetTypeId or AVATAR_BACKGROUND_ASSET_TYPE_ID,
				}
				table.insert(results, catalogItem)
			else
				warn(string.format("[BackgroundCatalog] Nao foi possivel obter info do asset %d", assetId))
			end
		end
	end

	return results
end

--[[
	Busca itens do catalogo de Planos de Fundo (Backgrounds)
	Parametros: params (SearchParams) - filtros de busca
	Retorna: {CatalogItem} - lista de itens formatados
]]
function CatalogService.SearchCatalog(params: SearchParams): ({CatalogItem}, string?)
	lastSearchParams = params

	local results: {CatalogItem} = {}
	local searchErrorCode: string? = nil

	-- 1. Buscar os backgrounds em destaque via IDs especificos
	local featuredItems = fetchFeaturedBackgrounds()
	for _, item in ipairs(featuredItems) do
		table.insert(results, item)
	end

	print(string.format("[BackgroundCatalog] Featured items: %d", #featuredItems))

	-- 2. Buscar via AvatarEditorService:SearchCatalogAsync (catalogo do Roblox)
	-- Buscamos por keyword e entao FILTRAMOS rigorosamente para apenas AvatarBackgrounds
	local searchParams = CatalogSearchParams.new()

	local keyword = params.Keyword or ""
	if keyword == "" then
		keyword = "avatar background"
	end
	searchParams.SearchKeyword = keyword

	-- Tipo de ordenacao
	local sortKey = params.SortType or "Relevância"
	searchParams.SortType = SORT_MAP[sortKey] or Enum.CatalogSortType.Relevance

	-- Categoria de filtro - All busca em todas as categorias (incluindo backgrounds)
	searchParams.CategoryFilter = Enum.CatalogCategoryFilter.None

	-- Incluir itens fora de venda para ter mais resultados
	searchParams.IncludeOffSale = false

	-- Limite maximo de resultados por pagina
	searchParams.Limit = 60

	-- Usar SearchCatalogAsync (metodo recomendado)
	local success, searchResult = pcall(function()
		return AvatarEditorService:SearchCatalogAsync(searchParams)
	end)

	-- Fallback para SearchCatalog (deprecated mas funcional)
	if not success then
		print("[BackgroundCatalog] SearchCatalogAsync falhou, tentando SearchCatalog...")
		success, searchResult = pcall(function()
			return AvatarEditorService:SearchCatalog(searchParams)
		end)
	end

	if not success then
		warn("[BackgroundCatalog] Erro na busca AvatarEditor: " .. tostring(searchResult))
		searchErrorCode = ERROR_CODES.ROBLOX_SEARCH_FAILED
	end

	if success and searchResult then
		local items = {}
		pcall(function()
			items = searchResult:GetCurrentPage()
		end)

		print(string.format("[BackgroundCatalog] Busca AvatarEditor retornou %d itens", #items))

		for _, item in ipairs(items) do
			-- O formato de resposta tem AssetType como string (nao AssetTypeId como numero)
			local itemType = item.AssetType or item.AssetTypeId
			local isBackground = isBackgroundAssetType(itemType)

			-- FILTRAR RIGOROSAMENTE: apenas incluir items que sao AvatarBackgrounds
			-- Isto evita que itens de outros tipos (shirts, hats, etc) aparecam no catalogo
			if not isBackground then
				continue
			end

			local catalogItem: CatalogItem = {
				AssetId = item.Id or 0,
				Name = item.Name or "No name",
				CreatorName = item.CreatorName or "Unknown",
				Price = item.Price or 0,
				ReleaseDate = item.ReleaseDate or item.Created or "---",
				Description = item.Description or "No description",
				ThumbnailUrl = "",
				AssetTypeId = AVATAR_BACKGROUND_ASSET_TYPE_ID,
			}

			-- Pular duplicatas (featured items ja estao na lista)
			local isDuplicate = false
			for _, existing in ipairs(results) do
				if existing.AssetId == catalogItem.AssetId then
					isDuplicate = true
					break
				end
			end
			if isDuplicate then continue end

			-- Filtrar por faixa de preco
			if params.MinPrice and catalogItem.Price < params.MinPrice then
				continue
			end
			if params.MaxPrice and catalogItem.Price > params.MaxPrice then
				continue
			end

			-- Filtrar por criador
			if params.CreatorFilter and params.CreatorFilter ~= "" then
				if not string.find(string.lower(catalogItem.CreatorName), string.lower(params.CreatorFilter)) then
					continue
				end
			end

			catalogItem.ThumbnailUrl = string.format(
				"rbxthumb://type=Asset&id=%d&w=420&h=420",
				catalogItem.AssetId
			)

			table.insert(results, catalogItem)
		end

		-- Se a busca nao retornou itens suficientes, tentar paginar
		if #items > 0 and #items >= 30 then
			local hasMore = true
			local pagesIterated = 0
			while hasMore and pagesIterated < 3 do
				hasMore = false
				pcall(function()
					hasMore = searchResult:AdvanceToNextPageAsync()
				end)
				if hasMore then
					local moreItems = {}
					pcall(function()
						moreItems = searchResult:GetCurrentPage()
					end)
					for _, item in ipairs(moreItems) do
						local catalogItem: CatalogItem = {
							AssetId = item.Id or 0,
							Name = item.Name or "No name",
							CreatorName = item.CreatorName or "Unknown",
							Price = item.Price or 0,
							ReleaseDate = "---",
							Description = item.Description or "No description",
							ThumbnailUrl = string.format("rbxthumb://type=Asset&id=%d&w=420&h=420", item.Id or 0),
							AssetTypeId = AVATAR_BACKGROUND_ASSET_TYPE_ID,
						}

						local isDup = false
						for _, existing in ipairs(results) do
							if existing.AssetId == catalogItem.AssetId then isDup = true break end
						end
						if not isDup then
							-- Aplicar filtros
							if params.MinPrice and catalogItem.Price < params.MinPrice then continue end
							if params.MaxPrice and catalogItem.Price > params.MaxPrice then continue end
							if params.CreatorFilter and params.CreatorFilter ~= "" then
								if not string.find(string.lower(catalogItem.CreatorName), string.lower(params.CreatorFilter)) then continue end
							end
							table.insert(results, catalogItem)
						end
					end
				end
				pagesIterated = pagesIterated + 1
			end
		end
	end

	-- Se ainda nao temos resultados suficientes, adicionar IDs de backgrounds conhecidos
	if #results < 4 then
		print("[BackgroundCatalog] Poucos resultados, adicionando backgrounds conhecidos...")
		-- Ja temos os featured, mas vamos garantir que aparecem mesmo se a API falhar
		local knownBackgrounds = {
			{ id = 121199209890990, name = "Plano de Fundo 1", creator = "Roblox", price = 0 },
			{ id = 116956243809295, name = "Plano de Fundo 2", creator = "Roblox", price = 0 },
			{ id = 139579276427743, name = "Plano de Fundo 3", creator = "Roblox", price = 0 },
			{ id = 132272208178794, name = "Plano de Fundo 4", creator = "Roblox", price = 0 },
		}
		for _, bg in ipairs(knownBackgrounds) do
			local alreadyExists = false
			for _, existing in ipairs(results) do
				if existing.AssetId == bg.id then alreadyExists = true break end
			end
			if not alreadyExists then
				table.insert(results, {
					AssetId = bg.id,
					Name = bg.name,
					CreatorName = bg.creator,
					Price = bg.price,
					ReleaseDate = "---",
					Description = "No description",
					ThumbnailUrl = string.format("rbxthumb://type=Asset&id=%d&w=420&h=420", bg.id),
					AssetTypeId = AVATAR_BACKGROUND_ASSET_TYPE_ID,
				})
			end
		end
	end

	-- Aplicar ordenacao local em todos os resultados (featured + API + fallback)
	local sortKey = params.SortType or "Relevância"
	if sortKey == "Menor Preço" or sortKey == "Menor Preco" then
		table.sort(results, function(a, b)
			return (a.Price or 0) < (b.Price or 0)
		end)
	elseif sortKey == "Maior Preço" or sortKey == "Maior Preco" then
		table.sort(results, function(a, b)
			return (a.Price or 0) > (b.Price or 0)
		end)
	elseif sortKey == "Lançamentos Recentes" or sortKey == "Lancamentos Recentes" then
		table.sort(results, function(a, b)
			return (a.ReleaseDate or "") > (b.ReleaseDate or "")
		end)
	end
	-- "Relevância" mantem a ordem original (API + featured)

	print(string.format("[BackgroundCatalog] Total de resultados: %d (ordenado por: %s)", #results, sortKey))
	itemCache = results

	-- If we got zero results and the search had errors, return the error code
	if #results == 0 and searchErrorCode then
		return results, searchErrorCode
	elseif #results == 0 then
		-- No results but no explicit error - still report as marketplace outdated
		return results, ERROR_CODES.MARKETPLACE_OUTDATED
	end

	return results, nil
end

--[[
	Busca informacoes detalhadas de um asset especifico
	Parametros: assetId (number) - ID do asset
	Retorna: CatalogItem? - informacoes do item ou nil
]]
function CatalogService.GetAssetInfo(assetId: number): (CatalogItem?, string?)
	-- Verificar cache primeiro
	for _, item in ipairs(itemCache) do
		if item.AssetId == assetId then
			return item, nil
		end
	end

	-- Tentar AvatarEditorService:GetItemDetailsAsync primeiro (suporta novos IDs)
	local success, item = pcall(function()
		return AvatarEditorService:GetItemDetailsAsync(assetId, Enum.AvatarItemType.Asset)
	end)

	if success and item then
		local catalogItem: CatalogItem = {
			AssetId = assetId,
			Name = item.Name or "No name",
			CreatorName = item.CreatorName or "Unknown",
			Price = item.Price or 0,
			ReleaseDate = "---",
			Description = item.Description or "No description",
			ThumbnailUrl = string.format(
				"rbxthumb://type=Asset&id=%d&w=420&h=420",
				assetId
			),
			AssetTypeId = AVATAR_BACKGROUND_ASSET_TYPE_ID,
		}
		return catalogItem, nil
	end

	-- Fallback: MarketplaceService:GetProductInfo
	local mpSuccess, info = pcall(function()
		return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
	end)

	if mpSuccess and info then
		local catalogItem: CatalogItem = {
			AssetId = assetId,
			Name = info.Name or "No name",
			CreatorName = info.Creator and info.Creator.Name or "Unknown",
			Price = info.PriceInRobux or 0,
			ReleaseDate = info.Created or "---",
			Description = info.Description or "No description",
			ThumbnailUrl = string.format(
				"rbxthumb://type=Asset&id=%d&w=420&h=420",
				assetId
			),
			AssetTypeId = info.AssetTypeId or 0,
		}
		return catalogItem, nil
	end

	-- Both AvatarEditorService and MarketplaceService failed for this asset
	return nil, ERROR_CODES.MARKETPLACE_OUTDATED
end

--[[
	Retorna os itens em cache da ultima busca
	Retorna: {CatalogItem}
]]
function CatalogService.GetCachedItems(): {CatalogItem}
	return itemCache
end

--[[
	Retorna os parametros da ultima busca
	Retorna: SearchParams
]]
function CatalogService.GetLastSearchParams(): SearchParams
	return lastSearchParams
end

return CatalogService
