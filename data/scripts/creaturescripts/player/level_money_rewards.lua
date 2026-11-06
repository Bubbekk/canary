-- One-time gold rewards for reaching milestone levels.
-- Each reward is granted once per account (first character to reach it),
-- tracked per character as well, and deposited into the bank.
local rewards = {
	{ level = 20, amount = 30000 },
	{ level = 100, amount = 100000 },
}

local levelMoneyRewards = CreatureEvent("LevelMoneyRewards")

function levelMoneyRewards.onAdvance(player, skill, oldLevel, newLevel)
	if skill ~= SKILL_LEVEL or newLevel <= oldLevel then
		return true
	end

	local accountKV = kv.scoped("level-money-rewards"):scoped("account-" .. player:getAccountId())
	local playerKV = player:kv():scoped("level-money-rewards")

	for _, reward in ipairs(rewards) do
		local key = "level-" .. reward.level
		if oldLevel < reward.level and newLevel >= reward.level and not playerKV:get(key) then
			playerKV:set(key, true)
			if accountKV:get(key) then
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Your account already received the level %d reward.", reward.level))
			else
				accountKV:set(key, player:getName())
				player:setBankBalance(player:getBankBalance() + reward.amount)
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Congratulations on reaching level %d! %d gold has been deposited into your bank account.", reward.level, reward.amount))
				logger.info("[LevelMoneyRewards] {} received {} gold for level {}", player:getName(), reward.amount, reward.level)
			end
		end
	end
	return true
end

levelMoneyRewards:register()
