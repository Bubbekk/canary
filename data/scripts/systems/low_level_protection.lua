-- Low level protection: players up to level 50 never really die. A lethal hit is cancelled and the player
-- is sent to their temple with full health and no mana, keeping level, skills, items and blessings.
-- The killer gets no frag or experience because there is no death. Rule: data/libs/systems/low_level_protection_core.lua
local Core = LowLevelProtectionCore

local CLEARED_CONDITIONS = { CONDITION_POISON, CONDITION_FIRE, CONDITION_ENERGY, CONDITION_BLEEDING, CONDITION_PARALYZE, CONDITION_DROWN, CONDITION_FREEZING, CONDITION_DAZZLED, CONDITION_CURSED, CONDITION_INFIGHT }

local pending = {} -- [guid] = true while the teleport is scheduled, so extra hits in the same tick are ignored

local function inBattleRoyale(player)
	local match = BattleRoyale and BattleRoyale.match
	local entry = match and match.players[player:getGuid()]
	return entry ~= nil and entry.alive
end

local function sendToTemple(guid)
	pending[guid] = nil
	local player = Player(guid)
	if not player then
		return
	end
	for _, condition in ipairs(CLEARED_CONDITIONS) do
		player:removeCondition(condition)
	end
	local town = player:getTown()
	local temple = town and town:getTemplePosition()
	player:getPosition():sendMagicEffect(CONST_ME_POFF)
	if temple then
		player:teleportTo(temple)
	end
	player:addHealth(player:getMaxHealth() - player:getHealth())
	player:addMana(-player:getMana())
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Fuiste derrotado. Hasta nivel %d est\225s protegido: no pierdes nivel, skills ni objetos.", Core.maxLevel))
end

local protection = CreatureEvent("LowLevelProtection")
function protection.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local player = creature and creature:getPlayer()
	if not player then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local guid = player:getGuid()
	if pending[guid] then
		return 0, primaryType, 0, secondaryType
	end
	local damage = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if not Core.shouldProtect(player:getLevel(), player:getHealth(), damage, primaryType == COMBAT_HEALING, inBattleRoyale(player)) then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	pending[guid] = true
	if attacker and attacker:isPlayer() then
		attacker:sendTextMessage(MESSAGE_STATUS, string.format("Derrotaste a %s (protecci\243n de bajo nivel: vuelve a su templo).", player:getName()))
	end
	addEvent(sendToTemple, 0, guid)
	return 0, primaryType, 0, secondaryType
end
protection:register()

local login = CreatureEvent("LowLevelProtectionLogin")
function login.onLogin(player)
	player:registerEvent("LowLevelProtection")
	if player:getLevel() <= Core.maxLevel then
		player:sendTextMessage(MESSAGE_STATUS, string.format("Protecci\243n de bajo nivel activa hasta nivel %d: al morir vuelves al templo sin perder nada.", Core.maxLevel))
	end
	return true
end
login:register()

local logout = CreatureEvent("LowLevelProtectionLogout")
function logout.onLogout(player)
	pending[player:getGuid()] = nil
	return true
end
logout:register()
