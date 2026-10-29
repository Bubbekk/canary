local premiumCategoryName = "Premium Time"
local premiumOfferName = "Premium Time"

if configManager.getBoolean(configKeys.VIP_SYSTEM_ENABLED) then
	premiumCategoryName = "VIP Shop"
	premiumOfferName = "VIP"
end

local premiumDescription =
	"<i>Enhance your gaming experience by gaining additional abilities and advantages:</i>\n\n&#8226; access to Premium areas\n&#8226; use Tibia's transport system (ships, carpet)\n&#8226; more spells\n&#8226; rent houses\n&#8226; found guilds\n&#8226; offline training\n&#8226; larger depots\n&#8226; and many more\n\n{usablebyallicon} valid for all characters on this account\n{activated}"

if configManager.getBoolean(configKeys.VIP_SYSTEM_ENABLED) then
	local vipBonusExp = configManager.getNumber(configKeys.VIP_BONUS_EXP)
	local vipBonusLoot = configManager.getNumber(configKeys.VIP_BONUS_LOOT)
	local vipBonusSkill = configManager.getNumber(configKeys.VIP_BONUS_SKILL)
	local vipStayOnline = configManager.getBoolean(configKeys.VIP_STAY_ONLINE)

	premiumDescription = "<i>Enhance your gaming experience by gaining advantages:</i>\n\n"
	premiumDescription = premiumDescription .. "&#8226; all Premium benefits (areas, spells, travel, houses, guilds)\n"
	if vipBonusExp > 0 then
		premiumDescription = premiumDescription .. "&#8226; +" .. vipBonusExp .. "% experience rate\n"
	end
	if vipBonusSkill > 0 then
		premiumDescription = premiumDescription .. "&#8226; +" .. vipBonusSkill .. "% skill training speed\n"
	end
	if vipBonusLoot > 0 then
		premiumDescription = premiumDescription .. "&#8226; +" .. vipBonusLoot .. "% loot\n"
	end
	if vipStayOnline then
		premiumDescription = premiumDescription .. "&#8226; stay online idle without getting disconnected\n"
	end
	if configManager.getBoolean(configKeys.AUTOLOOT) and configManager.getBoolean(configKeys.VIP_AUTOLOOT_VIP_ONLY) then
		premiumDescription = premiumDescription .. "&#8226; automatic loot\n"
	end
	if configManager.getBoolean(configKeys.VIP_KEEP_HOUSE) then
		premiumDescription = premiumDescription .. "&#8226; keep your house without premium time\n"
	end
	local familiarReduction = configManager.getNumber(configKeys.VIP_FAMILIAR_TIME_COOLDOWN_REDUCTION)
	if familiarReduction > 0 then
		premiumDescription = premiumDescription .. "&#8226; familiar cooldown reduced by " .. familiarReduction .. " minutes\n"
	end
	premiumDescription = premiumDescription .. "&#8226; +50% daily reward\n"
	premiumDescription = premiumDescription .. "&#8226; " .. GameStore.VIP_STORE_DISCOUNT_PERCENT .. "% discount on consumables in the Store\n"
	premiumDescription = premiumDescription .. "&#8226; more Tibia Coins for being online\n"
	premiumDescription = premiumDescription .. "&#8226; no daily limit on XP Boost purchases\n"
	premiumDescription = premiumDescription .. "\n{usablebyallicon} valid for all characters on this account\n{activated}"
end

return {
	icons = { "Category_PremiumTime.png" },
	name = premiumCategoryName,
	rookgaard = true,
	state = GameStore.States.STATE_NONE,
	-- Ordenadas de menor a mayor precio. Los días que se suman son id - 3000
	-- (ver processPremiumPurchase); "permanente" usa el máximo que admite la cuenta (65534 días).
	offers = {
		{
			icons = { "Premium_Time_30.png" },
			name = string.format("1 Day of %s", premiumOfferName),
			price = 0,
			id = GameStore.FREE_PREMIUM_DAY_OFFER_ID,
			validUntil = 1,
			description = premiumDescription,
			type = GameStore.OfferTypes.OFFER_TYPE_PREMIUM,
		},
		{
			icons = { "Premium_Time_90.png" },
			name = string.format("1 Week of %s", premiumOfferName),
			price = 75,
			id = 3007,
			validUntil = 7,
			description = premiumDescription,
			type = GameStore.OfferTypes.OFFER_TYPE_PREMIUM,
		},
		{
			icons = { "Premium_Time_180.png" },
			name = string.format("1 Month of %s", premiumOfferName),
			price = 250,
			id = 3030,
			validUntil = 30,
			description = premiumDescription,
			type = GameStore.OfferTypes.OFFER_TYPE_PREMIUM,
		},
		{
			icons = { "Premium_Time_360.png" },
			name = string.format("Permanent %s", premiumOfferName),
			price = 5000,
			id = 3000 + GameStore.PERMANENT_PREMIUM_DAYS,
			validUntil = GameStore.PERMANENT_PREMIUM_DAYS,
			description = premiumDescription,
			type = GameStore.OfferTypes.OFFER_TYPE_PREMIUM,
		},
	},
}
