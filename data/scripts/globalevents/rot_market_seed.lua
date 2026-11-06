-- RoT market seed: keeps anonymous sale offers from the "RoT Merchant" character
-- (an account nobody can log into) so the market always has basic equipment.
-- Prices are 1.5x (common) or 2x (rare drops) of the best NPC buy price, so items
-- can never be resold to an NPC for profit. Gold paid goes to the merchant and
-- leaves the economy. Generated from tools/market-seed/market_items.csv.
local MERCHANT_NAME = "RoT Merchant"
-- Restock only on these weekdays (os.date wday: 1 = Sunday ... 7 = Saturday): Monday and Thursday.
local RESTOCK_DAYS = { [2] = true, [5] = true }
local seedKV = kv.scoped("rot-market-seed")

-- { itemId, price, stock }
local offers = {
	{ 3366, 135000, 3 }, -- magic plate armor
	{ 11693, 120000, 2 }, -- blade of corruption
	{ 8057, 110000, 2 }, -- divine plate
	{ 3414, 100000, 2 }, -- mastermind shield
	{ 22726, 100000, 2 }, -- rift shield
	{ 3340, 100000, 2 }, -- heavy mace
	{ 11651, 100000, 2 }, -- elite draken mail
	{ 11674, 100000, 2 }, -- cobra crown
	{ 8039, 100000, 2 }, -- dragon robe
	{ 22867, 90000, 2 }, -- rift crossbow
	{ 22866, 90000, 2 }, -- rift bow
	{ 5803, 84000, 2 }, -- arbalest
	{ 7403, 80000, 2 }, -- berserker
	{ 3386, 80000, 2 }, -- dragon scale mail
	{ 4033, 80000, 2 }, -- draken boots
	{ 7382, 72000, 2 }, -- demonrage sword
	{ 16163, 70000, 2 }, -- crystal crossbow
	{ 16164, 70000, 2 }, -- mycological bow
	{ 10390, 60000, 2 }, -- Zaoan sword
	{ 3364, 60000, 2 }, -- golden legs
	{ 7388, 60000, 2 }, -- vile axe
	{ 6553, 67500, 3 }, -- ruthless axe
	{ 10385, 67500, 3 }, -- Zaoan helmet
	{ 14246, 56000, 2 }, -- hive bow
	{ 5741, 60000, 3 }, -- skull helmet
	{ 8027, 50000, 2 }, -- composite hornbow
	{ 7418, 52500, 3 }, -- nightmare blade
	{ 10323, 52500, 3 }, -- guardian boots
	{ 14088, 48000, 3 }, -- carapace shield
	{ 22727, 45000, 3 }, -- rift lance
	{ 7414, 40000, 2 }, -- abyss hammer
	{ 3360, 40000, 2 }, -- golden armor
	{ 3554, 45000, 3 }, -- steel boots
	{ 3420, 45000, 3 }, -- demon shield
	{ 3332, 45000, 3 }, -- hammer of wrath
	{ 3392, 45000, 3 }, -- royal helmet
	{ 7416, 45000, 3 }, -- bloody edge
	{ 11657, 42000, 3 }, -- twiceslicer
	{ 7383, 37500, 3 }, -- relic sword
	{ 7422, 37500, 3 }, -- jade hammer
	{ 7419, 30000, 2 }, -- dreaded cleaver
	{ 7402, 30000, 2 }, -- dragon slayer
	{ 8063, 30000, 2 }, -- paladin armor
	{ 14087, 30000, 2 }, -- grasshopper legs
	{ 7421, 33000, 3 }, -- onyx flail
	{ 21173, 28000, 2 }, -- moohtant cudgel
	{ 7404, 30000, 3 }, -- assassin dagger
	{ 7412, 27000, 3 }, -- butcher's axe
	{ 8061, 27000, 3 }, -- skullcracker armor
	{ 10439, 24000, 2 }, -- Zaoan robe
	{ 8029, 24000, 2 }, -- silkweaver bow
	{ 3382, 24000, 2 }, -- crown legs
	{ 3281, 25500, 3 }, -- giant sword
	{ 14089, 25500, 3 }, -- hive scythe
	{ 10389, 25000, 3 }, -- traditional sai
	{ 8050, 24000, 3 }, -- crystalline armor
	{ 8052, 24000, 3 }, -- swamplair armor
	{ 21981, 22500, 3 }, -- oriental shoes
	{ 21892, 20000, 2 }, -- crest of the deep seas
	{ 14086, 22500, 3 }, -- calopteryx cape
	{ 10384, 21000, 3 }, -- Zaoan armor
	{ 10387, 21000, 3 }, -- Zaoan legs
	{ 8074, 19500, 3 }, -- spellbook of mind control
	{ 14247, 18000, 3 }, -- ornate crossbow
	{ 3381, 18000, 3 }, -- crown armor
	{ 3333, 18000, 3 }, -- crystal mace
	{ 3342, 18000, 3 }, -- war axe
	{ 25699, 18000, 3 }, -- wooden spellbook
	{ 10438, 18000, 3 }, -- spellweaver's robe
	{ 7386, 18000, 3 }, -- mercenary sword
	{ 21176, 18000, 3 }, -- execowtioner axe
	{ 9103, 16000, 2 }, -- batwing hat
	{ 22086, 15000, 2 }, -- badger boots
	{ 3408, 15000, 2 }, -- bonelord helmet
	{ 823, 16500, 3 }, -- glacier kilt
	{ 824, 16500, 3 }, -- glacier robe
	{ 3315, 16500, 3 }, -- guardian halberd
	{ 21165, 16500, 3 }, -- rubber cap
	{ 826, 16500, 3 }, -- magma coat
	{ 21168, 16500, 3 }, -- alloy legs
	{ 821, 16500, 3 }, -- magma legs
	{ 812, 16500, 3 }, -- terra legs
	{ 811, 16500, 3 }, -- terra mantle
	{ 822, 16500, 3 }, -- lightning legs
	{ 825, 16500, 3 }, -- lightning robe
	{ 3567, 15000, 3 }, -- blue robe
	{ 7428, 15000, 3 }, -- bonebreaker
	{ 21167, 15000, 3 }, -- heat core
	{ 7456, 15000, 3 }, -- noble axe
	{ 10388, 15000, 3 }, -- drakinata
	{ 7451, 15000, 3 }, -- shadow sceptre
	{ 14042, 13500, 3 }, -- warrior's shield
	{ 14043, 13500, 3 }, -- guardian axe
	{ 21171, 13500, 3 }, -- metal bat
	{ 7427, 13500, 3 }, -- chaos mace
	{ 10451, 13500, 3 }, -- jade hat
	{ 3436, 13500, 3 }, -- medusa shield
	{ 7407, 12000, 3 }, -- haunted blade
	{ 3428, 12000, 3 }, -- tower shield
	{ 3326, 12000, 3 }, -- epee
	{ 3320, 12000, 3 }, -- fire axe
	{ 3419, 12000, 3 }, -- crown shield
	{ 7426, 12000, 3 }, -- amber staff
	{ 8073, 12000, 3 }, -- spellbook of warding
	{ 7424, 10000, 2 }, -- lunar staff
	{ 9653, 10000, 2 }, -- witch hat
	{ 3435, 10000, 2 }, -- castle shield
	{ 14250, 10500, 3 }, -- deepling squelcher
	{ 7437, 10500, 3 }, -- sapphire hammer
	{ 17829, 10500, 3 }, -- buckle
	{ 21174, 10500, 3 }, -- mino lance
	{ 16096, 9800, 3 }, -- wand of defiance
	{ 16118, 9800, 3 }, -- glacial rod
	{ 3324, 9000, 3 }, -- skull staff
	{ 16115, 9000, 3 }, -- wand of everblazing
	{ 3391, 9000, 3 }, -- crusader helmet
	{ 8043, 9000, 3 }, -- focus cape
	{ 3416, 8000, 2 }, -- dragon shield
	{ 21166, 9000, 3 }, -- mooh'tah plate
	{ 7463, 9000, 3 }, -- mammoth fur cape
	{ 16117, 9000, 3 }, -- muck rod
	{ 8082, 6600, 3 }, -- underworld rod
	{ 8094, 6600, 3 }, -- wand of voodoo
	{ 22183, 7200, 2 }, -- ogre scepta
	{ 3370, 7500, 3 }, -- knight armor
	{ 3369, 7500, 3 }, -- warrior helmet
	{ 21170, 7500, 3 }, -- gearwheel chain
	{ 3371, 7500, 3 }, -- knight legs
	{ 7452, 7500, 3 }, -- spiked squelcher
	{ 10386, 7500, 3 }, -- Zaoan shoes
	{ 3575, 7500, 3 }, -- wood cape
	{ 25700, 7500, 3 }, -- dream blossom staff
	{ 22085, 7500, 3 }, -- fur armor
	{ 7436, 7500, 3 }, -- angelic axe
	{ 8092, 5400, 3 }, -- wand of starstorm
	{ 8084, 5400, 3 }, -- springsprout rod
	{ 5461, 6000, 2 }, -- pirate boots
	{ 13987, 6000, 3 }, -- deepling staff
	{ 7413, 6000, 3 }, -- titan axe
	{ 8072, 6000, 3 }, -- spellbook of enlightenment
	{ 3280, 6000, 3 }, -- fire sword
	{ 17828, 6000, 3 }, -- pair of iron fists
	{ 3067, 4500, 3 }, -- hailstorm rod
	{ 3071, 4500, 3 }, -- wand of inferno
	{ 22171, 5000, 2 }, -- ogre klubba
	{ 21172, 5000, 2 }, -- glooth whip
	{ 7454, 4500, 3 }, -- glorious axe
	{ 7430, 4500, 3 }, -- dragonbone staff
	{ 7387, 4500, 3 }, -- diamond sceptre
	{ 22192, 4000, 2 }, -- shamanic mask
	{ 21175, 4500, 3 }, -- mino shield
	{ 7438, 4000, 2 }, -- elvish bow
	{ 7457, 4000, 2 }, -- fur boots
	{ 3440, 4000, 2 }, -- scarab shield
	{ 3073, 3000, 3 }, -- wand of cosmic energy
	{ 829, 3800, 3 }, -- glacier mask
	{ 818, 3800, 3 }, -- magma boots
	{ 3385, 3800, 3 }, -- crown helmet
	{ 813, 3800, 3 }, -- terra boots
	{ 820, 3800, 3 }, -- lightning boots
	{ 3055, 3800, 3 }, -- platinum amulet
	{ 827, 3800, 3 }, -- magma monocle
	{ 830, 3800, 3 }, -- terra hood
	{ 819, 3800, 3 }, -- glacier shoes
	{ 828, 3800, 3 }, -- lightning headband
	{ 21177, 3800, 3 }, -- cowtana
	{ 7460, 3000, 2 }, -- norse shield
	{ 22172, 3000, 2 }, -- ogre choppa
	{ 7379, 3000, 2 }, -- brutetamer's staff
	{ 22087, 3000, 2 }, -- wereboar loincloth
	{ 7408, 3000, 2 }, -- wyvern fang
	{ 12683, 3000, 3 }, -- heavy trident
	{ 21169, 3000, 3 }, -- metal spats
	{ 3415, 3000, 3 }, -- guardian shield
	{ 3318, 3000, 3 }, -- knight axe
	{ 3322, 3000, 3 }, -- dragon hammer
	{ 25698, 3000, 3 }, -- butterfly ring
	{ 17852, 3000, 3 }, -- helmet of the lost
	{ 20184, 2900, 3 }, -- broken visor
	{ 8083, 2300, 3 }, -- northwind rod
	{ 8093, 2300, 3 }, -- wand of draconia
	{ 3404, 2000, 2 }, -- leopard armor
	{ 3344, 2300, 3 }, -- beastslayer axe
	{ 3348, 2000, 2 }, -- banana staff
	{ 3407, 1800, 2 }, -- charmer's tiara
	{ 3406, 1700, 2 }, -- feather headdress
	{ 3069, 1500, 3 }, -- necrotic rod
	{ 3072, 1500, 3 }, -- wand of decay
	{ 40535, 1400, 2 }, -- broken Iks spear
	{ 7432, 1500, 3 }, -- furry club
	{ 6299, 1500, 3 }, -- death ring
	{ 3306, 1500, 3 }, -- golden sickle
	{ 3356, 1500, 3 }, -- devil helmet
	{ 6096, 1500, 3 }, -- pirate hat
	{ 3556, 1500, 3 }, -- crocodile boots
	{ 3328, 1500, 3 }, -- daramian waraxe
	{ 3443, 1300, 3 }, -- tusk shield
	{ 40532, 1200, 2 }, -- broken Iks headpiece
	{ 3429, 1200, 3 }, -- black shield
	{ 40531, 1100, 2 }, -- broken Iks faulds
	{ 17846, 1200, 3 }, -- leather harness
	{ 3290, 1000, 2 }, -- silver dagger
	{ 7449, 900, 3 }, -- crystal sword
	{ 3373, 800, 3 }, -- strange helmet
	{ 10406, 800, 3 }, -- Zaoan halberd
	{ 3301, 800, 3 }, -- broadsword
	{ 10392, 800, 3 }, -- twin hooks
	{ 6095, 800, 3 }, -- pirate shirt
	{ 7425, 800, 3 }, -- taurus mace
}

local function getMerchantId()
	local resultId = db.storeQuery("SELECT `id` FROM `players` WHERE `name` = " .. db.escapeString(MERCHANT_NAME))
	if not resultId then
		return nil
	end
	local id = Result.getNumber(resultId, "id")
	Result.free(resultId)
	return id
end

local function refillMarket()
	local merchantId = getMerchantId()
	if not merchantId then
		logger.warn("[RoTMarketSeed] merchant character '{}' not found", MERCHANT_NAME)
		return
	end

	local now = os.time()
	-- Keep existing offers from expiring (expired offers would return items to the merchant depot).
	db.query("UPDATE `market_offers` SET `created` = " .. now .. " WHERE `player_id` = " .. merchantId)

	local current = {}
	local resultId = db.storeQuery("SELECT `itemtype`, SUM(`amount`) AS `total` FROM `market_offers` WHERE `player_id` = " .. merchantId .. " AND `sale` = 1 GROUP BY `itemtype`")
	if resultId then
		repeat
			current[Result.getNumber(resultId, "itemtype")] = Result.getNumber(resultId, "total")
		until not Result.next(resultId)
		Result.free(resultId)
	end

	local added = 0
	for _, offer in ipairs(offers) do
		local itemId, price, stock = offer[1], offer[2], offer[3]
		local missing = stock - (current[itemId] or 0)
		if missing > 0 then
			db.query(string.format("INSERT INTO `market_offers` (`player_id`, `sale`, `itemtype`, `amount`, `created`, `anonymous`, `price`, `tier`) VALUES (%d, 1, %d, %d, %d, 1, %d, 0)", merchantId, itemId, missing, now, price))
			added = added + missing
		end
	end
	seedKV:set("last-restock", now)
	logger.info("[RoTMarketSeed] market restocked ({} items added)", added)
end

local startup = GlobalEvent("RoTMarketSeedStartup")
function startup.onStartup()
	-- Only seed on the very first start; afterwards stock is replenished twice a week.
	if not seedKV:get("last-restock") then
		addEvent(refillMarket, 5000)
	end
	return true
end
startup:register()

local daily = GlobalEvent("RoTMarketSeedDaily")
function daily.onTime(interval)
	if RESTOCK_DAYS[os.date("*t").wday] then
		refillMarket()
	end
	return true
end
daily:time("12:00")
daily:register()
