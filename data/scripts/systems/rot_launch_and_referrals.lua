-- RoT growth incentives:
--  * Launch race: the first non-staff character to reach each milestone level wins Tibia Coins (once ever).
--  * Referrals: a new character says "!referido Name" to credit the player who invited them. When the new
--    character reaches REFERRAL_LEVEL, both accounts receive Tibia Coins. One referrer per account, the
--    referrer must be on another account and another IP, and each referrer has a monthly cap.
-- Coins are non-transferable so they can't be farmed and sold.

local RACE = {
	{ level = 100, coins = 50 },
	{ level = 150, coins = 100 },
	{ level = 200, coins = 200 },
	{ level = 300, coins = 500 },
}

local REFERRAL_LEVEL = 100
local REFERRAL_MAX_LEVEL_TO_REGISTER = 50
local REFERRER_COINS = 100
local REFERRED_COINS = 50
local REFERRER_MONTHLY_CAP = 10

local raceKV = kv.scoped("rot-launch-race")
local referralKV = kv.scoped("rot-referrals")

local function broadcast(message)
	Game.broadcastMessage(message, MESSAGE_GAME_HIGHLIGHT)
end

local function isStaff(player)
	return player:getGroup():getId() > 1
end

local function giveCoinsToAccount(accountId, coins, playerName)
	local target = playerName and Player(playerName)
	if target and target:getAccountId() == accountId then
		target:addTibiaCoins(coins)
		return
	end
	-- Offline (or another character of the account is online): credit the account in the database;
	-- an online character of that account picks it up on its next login.
	for _, online in ipairs(Game.getPlayers()) do
		if online:getAccountId() == accountId then
			online:addTibiaCoins(coins)
			return
		end
	end
	db.query(string.format("UPDATE `accounts` SET `coins` = `coins` + %d WHERE `id` = %d", coins, accountId))
end

local function monthKey()
	return os.date("%Y%m")
end

local advance = CreatureEvent("RoTGrowthAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill ~= SKILL_LEVEL or newLevel <= oldLevel or isStaff(player) then
		return true
	end

	for _, milestone in ipairs(RACE) do
		local key = "level-" .. milestone.level
		if oldLevel < milestone.level and newLevel >= milestone.level and not raceKV:get(key) then
			raceKV:set(key, player:getName())
			player:addTibiaCoins(milestone.coins)
			broadcast(string.format("[Launch Race] %s is the first player to reach level %d and wins %d Tibia Coins!", player:getName(), milestone.level, milestone.coins))
			logger.info("[RoTGrowth] launch race level {} won by {}", milestone.level, player:getName())
		end
	end

	if oldLevel < REFERRAL_LEVEL and newLevel >= REFERRAL_LEVEL then
		local accountKey = "account-" .. player:getAccountId()
		local referral = referralKV:get(accountKey)
		if type(referral) == "table" and not referral.paid and referral.referrerAccount then
			referral.paid = true
			referralKV:set(accountKey, referral)
			player:addTibiaCoins(REFERRED_COINS)
			giveCoinsToAccount(referral.referrerAccount, REFERRER_COINS, referral.referrerName)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[Referral] You reached level %d and received %d Tibia Coins. %s received %d Tibia Coins for inviting you!", REFERRAL_LEVEL, REFERRED_COINS, referral.referrerName, REFERRER_COINS))
			local referrer = Player(referral.referrerName)
			if referrer then
				referrer:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[Referral] %s reached level %d. You received %d Tibia Coins!", player:getName(), REFERRAL_LEVEL, REFERRER_COINS))
			end
			logger.info("[RoTGrowth] referral paid: {} -> {}", player:getName(), referral.referrerName)
		end
	end
	return true
end
advance:register()

local login = CreatureEvent("RoTGrowthLogin")
function login.onLogin(player)
	player:registerEvent("RoTGrowthAdvance")
	return true
end
login:register()

local referralCommand = TalkAction("!referido")
function referralCommand.onSay(player, words, param)
	local name = param:trim()
	if name == "" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Usage: !referido NombreDelPersonaje. If a friend invited you, both get Tibia Coins when you reach level %d (you must register it before level %d).", REFERRAL_LEVEL, REFERRAL_MAX_LEVEL_TO_REGISTER))
		return true
	end

	local accountKey = "account-" .. player:getAccountId()
	if referralKV:get(accountKey) then
		player:sendCancelMessage("Your account already has a referrer.")
		return true
	end
	if player:getLevel() > REFERRAL_MAX_LEVEL_TO_REGISTER then
		player:sendCancelMessage(string.format("You can only register a referrer before level %d.", REFERRAL_MAX_LEVEL_TO_REGISTER))
		return true
	end

	local resultId = db.storeQuery("SELECT `id`, `name`, `account_id`, `lastip`, `group_id` FROM `players` WHERE `name` = " .. db.escapeString(name))
	if not resultId then
		player:sendCancelMessage("That character does not exist.")
		return true
	end
	local referrerName = Result.getString(resultId, "name")
	local referrerAccount = Result.getNumber(resultId, "account_id")
	local referrerIp = Result.getNumber(resultId, "lastip")
	Result.free(resultId)

	if referrerAccount == player:getAccountId() then
		player:sendCancelMessage("You can't refer yourself.")
		return true
	end
	if referrerIp ~= 0 and referrerIp == player:getIp() then
		player:sendCancelMessage("The referrer can't use the same connection as you.")
		return true
	end

	local capKey = string.format("referrer-%d-%s", referrerAccount, monthKey())
	local used = referralKV:get(capKey) or 0
	if used >= REFERRER_MONTHLY_CAP then
		player:sendCancelMessage("That player has reached the referral limit for this month.")
		return true
	end

	referralKV:set(capKey, used + 1)
	referralKV:set(accountKey, { referrerAccount = referrerAccount, referrerName = referrerName, paid = false, at = os.time() })
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[Referral] %s is now your referrer. When you reach level %d you get %d Tibia Coins and %s gets %d.", referrerName, REFERRAL_LEVEL, REFERRED_COINS, referrerName, REFERRER_COINS))
	return true
end
referralCommand:separator(" ")
referralCommand:groupType("normal")
referralCommand:register()
