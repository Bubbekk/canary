-- Bestiario VIP: las cuentas VIP suman kills extra en el bestiario (no en el bosstiario).
-- Con bestiaryKillMultiplier = 3 en config.lua, un VIP cuenta 3 + VIP_EXTRA_KILLS = 5 por monstruo.
-- El servidor ya llama a este callback solo para monstruos no invocados (igual que el bestiario normal).
local VIP_EXTRA_KILLS = 2

local callback = EventCallback("VipBestiaryPlayerOnKill")

function callback.playerOnKill(player, monster)
	if not player or not monster or not configManager.getBoolean(configKeys.VIP_SYSTEM_ENABLED) or not player:isVip() then
		return
	end

	local monsterType = monster:getType()
	if not monsterType or monsterType:raceId() == 0 or monsterType:bossRace() then
		return
	end

	player:addBestiaryKill(monsterType:name(), VIP_EXTRA_KILLS)
end

callback:register()
