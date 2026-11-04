--[[
Items have been updated so that if the offer type is not one of the types: OFFER_TYPE_OUTFIT, OFFER_TYPE_OUTFIT_ADDON,
OFFER_TYPE_MOUNT, OFFER_TYPE_NAMECHANGE, OFFER_TYPE_SEXCHANGE, OFFER_TYPE_PROMOTION, OFFER_TYPE_EXPBOOST,
OFFER_TYPE_PREYSLOT, OFFER_TYPE_PREYBONUS, OFFER_TYPE_TEMPLE, OFFER_TYPE_BLESSINGS, OFFER_TYPE_PREMIUM,
OFFER_TYPE_ALLBLESSINGS
]]

-- Parser
dofile(CORE_DIRECTORY .. "/modules/scripts/gamestore/init.lua")
-- Config

local GameStore = require("gamestore.constants")
require("gamestore.helpers")

HomeBanners = {
	images = { "home/banner_armouredarcher.png", "home/banner_podiumoftenacity.png" },
	delay = 10,
}

-- GameStore.SearchCategory = {
-- 	icons = {},
-- 	name = "Search Results",
-- 	rookgaard = true,
-- 	state = GameStore.States.STATE_NONE,
-- }

local catalogLoader = dofile(CORE_DIRECTORY .. "/modules/scripts/gamestore/catalog_loader.lua")
local catalogModules = dofile(CORE_DIRECTORY .. "/modules/scripts/gamestore/catalog/init.lua")
local catalogBasePath = CORE_DIRECTORY .. "/modules/scripts/gamestore/catalog/"

for index, moduleEntry in ipairs(catalogModules) do
	local category
	local moduleName
	local sourceName

	if type(moduleEntry) == "string" then
		moduleName = moduleEntry
		category = dofile(catalogBasePath .. moduleName .. ".lua")
		sourceName = moduleEntry
	elseif type(moduleEntry) == "table" then
		if moduleEntry.module then
			moduleName = moduleEntry.module
			category = dofile(catalogBasePath .. moduleName .. ".lua")
			sourceName = moduleEntry.source or moduleName
		else
			category = moduleEntry
			sourceName = moduleEntry.name or string.format("catalog[%d]", index)
		end
	else
		logger.error("Invalid catalog entry at position {}", index)
	end

	if moduleName ~= nil and type(moduleName) ~= "string" then
		logger.error("Invalid catalog module name at position {}", index)
	end

	catalogLoader.registerCategory(category, sourceName or moduleName)
end

GameStore.Categories = catalogLoader.getCategories()

-- Precios personalizados de RoT (multiplicadores por categoría y overrides por id).
-- Se aplican antes de asignar ids dinámicos, por lo que también afecta a las
-- ofertas con precio en tabla (count/price múltiples).
local storePrices = dofile(CORE_DIRECTORY .. "/modules/scripts/gamestore/store_prices.lua")
local function applyStorePrices()
	local multipliers = storePrices.multipliers or {}
	local overrides = storePrices.overrides or {}
	local byId = overrides.byId or {}
	local byName = overrides.byName or {}

	for _, category in ipairs(GameStore.Categories) do
		if category.offers then
			for _, offer in ipairs(category.offers) do
				local fixed = byId[offer.id] or (offer.name and byName[offer.name])
				local multiplier = multipliers[category.name] or 1.0

				if fixed ~= nil then
					if type(offer.price) == "table" then
						for i = 1, #offer.price do
							offer.price[i] = fixed
						end
					else
						offer.price = fixed
					end
				elseif multiplier ~= 1.0 then
					if type(offer.price) == "table" then
						for i = 1, #offer.price do
							if type(offer.price[i]) == "number" and offer.price[i] > 0 then
								offer.price[i] = math.max(1, math.floor(offer.price[i] * multiplier + 0.5))
							end
						end
					elseif type(offer.price) == "number" and offer.price > 0 then
						offer.price = math.max(1, math.floor(offer.price * multiplier + 0.5))
					end
				end
			end
		end
	end

	-- La tabla de XP Boost se lee de forma dinámica en store.lua.
	GameStore.ExpBoostValuesCustom = storePrices.expBoost
end
applyStorePrices()

-- Las ofertas de las subcategorias de "Consumables" tienen descuento VIP
for _, category in ipairs(GameStore.Categories) do
	if category.parent == "Consumables" and category.offers then
		for _, offer in ipairs(category.offers) do
			offer.vipDiscount = true
		end
	end
end

-- Each outfit must be uniquely identified to distinguish between addons.
-- Here we dynamically assign ids for outfits. These ids must be unique.
local runningId = 45000
for k, category in ipairs(GameStore.Categories) do
	if category.offers then
		for m, offer in ipairs(category.offers) do
			if not offer.id then
				if type(offer.count) == "table" then
					for i = 1, #offer.price do
						offer.id[i] = runningId
						runningId = runningId + 1
					end
				else
					offer.id = runningId
					runningId = runningId + 1
				end
			end
			if not offer.type then
				offer.type = GameStore.OfferTypes.OFFER_TYPE_NONE
			end
			if not offer.coinType then
				offer.coinType = GameStore.CoinType.Transferable
			end
		end
	end
end
