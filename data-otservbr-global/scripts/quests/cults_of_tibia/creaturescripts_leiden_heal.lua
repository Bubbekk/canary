-- Leiden starts at half health and every player attack heals him. Once he is fully healed he turns
-- into Ravenous Hunger, the boss that actually completes the Barkless mission. Nothing performed that
-- transformation before, so Leiden could never be beaten and Ravenous Hunger never appeared (#2066).
local leidenHeal = CreatureEvent("LeidenHeal")

local function transformIntoRavenousHunger(leidenId)
	local leiden = Monster(leidenId)
	if not leiden or leiden:getHealth() < leiden:getMaxHealth() then
		return
	end

	local position = leiden:getPosition()
	leiden:remove()
	local boss = Game.createMonster("Ravenous Hunger", position, false, true)
	if boss then
		position:sendMagicEffect(CONST_ME_MORTAREA)
		boss:say("THE HUNGER AWAKENS!", TALKTYPE_MONSTER_YELL)
	end
end

function leidenHeal.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if attacker and attacker:isPlayer() then
		primaryType = COMBAT_HEALING
		secondaryType = primaryType
		if primaryDamage < 0 then
			primaryDamage = primaryDamage * -1
		end
		secondaryDamage = primaryDamage
		creature:addHealth(primaryDamage < 0 and -primaryDamage or primaryDamage)
		if creature:getHealth() >= creature:getMaxHealth() then
			-- Deferred: the creature must not be removed while its own health change is being processed
			addEvent(transformIntoRavenousHunger, 100, creature:getId())
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

leidenHeal:register()
