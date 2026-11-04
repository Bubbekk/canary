-- Characters created by copying a sample character (MyAAC does this) inherit the sample's store inbox
-- together with its owner, so the inbox refuses every owned store item ("this item is not yours").
-- On login, give the store inbox and the items inside it to the character that actually holds them.
local fixStoreInboxOwner = CreatureEvent("FixStoreInboxOwner")

function fixStoreInboxOwner.onLogin(player)
	local inbox = player:getStoreInbox()
	if not inbox then
		return true
	end

	local guid = player:getGuid()
	local fixed = 0
	if inbox:hasOwner() and inbox:getOwnerId() ~= guid then
		inbox:setOwner(player)
		fixed = fixed + 1
	end
	for _, item in ipairs(inbox:getItems(true)) do
		if item:hasOwner() and item:getOwnerId() ~= guid then
			item:setOwner(player)
			fixed = fixed + 1
		end
	end

	if fixed > 0 then
		logger.info("[FixStoreInboxOwner] {}: {} store inbox entries had another character as owner and were reassigned", player:getName(), fixed)
	end
	return true
end

fixStoreInboxOwner:register()
