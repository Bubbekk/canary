-- Goshnar's Greed must be invulnerable until the Greedbeasts are killed. Its script toggles this with
-- monster:immune(), but the source only stores that flag and never checks it when dealing damage, so
-- the boss could be hit from the start (#3500). This event enforces the flag.
local greedImmunity = CreatureEvent("GoshnarsGreedImmunity")

function greedImmunity.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local monster = creature:getMonster()
	if monster and monster:immune() and primaryType ~= COMBAT_HEALING then
		return 0, primaryType, 0, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

greedImmunity:register()
