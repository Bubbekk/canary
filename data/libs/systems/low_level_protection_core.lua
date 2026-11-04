-- Low level protection: up to this level a death sends the player to the temple instead of killing them
-- (no experience, skill, item or blessing loss), so low level players can fight without fear.
-- Pure rule, unit tested in tests/lua/test_low_level_protection_core.lua; game hook in
-- data/scripts/systems/low_level_protection.lua.
LowLevelProtectionCore = {
	maxLevel = 50,
}

-- damage is the absolute value of the incoming hit (primary + secondary)
function LowLevelProtectionCore.shouldProtect(level, health, damage, isHealing, inBattleRoyale)
	if isHealing or inBattleRoyale then
		return false
	end
	if level > LowLevelProtectionCore.maxLevel then
		return false
	end
	return damage >= health
end

return LowLevelProtectionCore
