-- Recompensas diarias VIP: una fila extra en el muro de recompensas, solo para cuentas VIP.
--
-- - Ciclo propio de 7 días, independiente del muro clásico (que sigue igual, con su +50% VIP).
-- - Una recompensa por CUENTA y por día (el día cambia en cada guardado del servidor),
--   así que no sirve crear varios personajes.
-- - Solo se reclama en un santuario de recompensas (nada de Acceso instantáneo).
-- - Se guarda al instante en MySQL (`vip_daily_reward`) con una actualización condicional y
--   un token de reclamo, de modo que dos personajes de la misma cuenta no pueden reclamar a la vez.
-- - Todo llega al buzón de la Tienda marcado como objeto de Tienda (no se puede comerciar).
--
-- Cliente <-> servidor: opcode extendido 120 (módulo game_rewardwall de OTClient).
--   Cliente -> servidor: "state" (pide el estado) | "claim:<opción>" (reclama el día actual)
--   Servidor -> cliente: "S|<vip 0/1>|<día 1-7>|<puede reclamar 0/1>|<en santuario 0/1>"
--                        "M|<mensaje>" (resultado o error)

VipDailyReward = VipDailyReward or {}

local OPCODE = 120
local SHRINE_VALID_SECONDS = 10 * 60
local SHRINE_MAX_DISTANCE = 3

-- Las opciones (choices) deben coincidir en orden con las del cliente.
local REWARDS = {
	[1] = { type = "items", choices = { { 236, 25 }, { 237, 25 } } }, -- strong health / strong mana potion
	[2] = { type = "prey", amount = 2 },
	[3] = { type = "exercise" },
	[4] = { type = "xpboost", minutes = 30 },
	[5] = { type = "tokens", amount = 1 },
	[6] = { type = "exercise" },
	[7] = { type = "chest", minutes = 60, coins = 5, tokens = 1 },
}

-- Armas de entrenamiento normales (500 cargas)
local EXERCISE_WEAPONS = { 28552, 28553, 28554, 28555, 28556, 28557 } -- sword, axe, club, bow, rod, wand
local EXERCISE_CHARGES = 500

local shrineVisits = {} -- [playerId] = { time = os.time(), pos = Position }
local tableReady = false

local function ensureTable()
	if not tableReady then
		tableReady = db.query("CREATE TABLE IF NOT EXISTS `vip_daily_reward` (`account_id` INT UNSIGNED NOT NULL, `day` TINYINT UNSIGNED NOT NULL DEFAULT 0, `last_claim_save` INT NOT NULL DEFAULT -1, `claim_token` INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4") == true
	end
	return tableReady
end

local function readRow(accountId)
	local resultId = db.storeQuery("SELECT `day`, `last_claim_save`, `claim_token` FROM `vip_daily_reward` WHERE `account_id` = " .. accountId)
	if not resultId then
		return { day = 0, lastClaimSave = -1, token = 0 }
	end
	local row = {
		day = Result.getNumber(resultId, "day") or 0,
		lastClaimSave = Result.getNumber(resultId, "last_claim_save") or -1,
		token = Result.getNumber(resultId, "claim_token") or 0,
	}
	Result.free(resultId)
	return row
end

local function isVip(player)
	return configManager.getBoolean(configKeys.VIP_SYSTEM_ENABLED) and player:isVip()
end

local function isAtShrine(player)
	local visit = shrineVisits[player:getId()]
	if not visit or os.time() - visit.time > SHRINE_VALID_SECONDS then
		return false
	end
	local pos = player:getPosition()
	return pos.z == visit.pos.z and math.abs(pos.x - visit.pos.x) <= SHRINE_MAX_DISTANCE and math.abs(pos.y - visit.pos.y) <= SHRINE_MAX_DISTANCE
end

local function sendMessage(player, text)
	player:sendExtendedOpcode(OPCODE, "M|" .. text)
end

function VipDailyReward.sendState(player)
	if not player:isUsingOtClient() or not ensureTable() then
		return
	end
	local row = readRow(player:getAccountId())
	local canClaim = isVip(player) and row.lastClaimSave < GetDailyRewardServerSaveCount()
	player:sendExtendedOpcode(OPCODE, string.format("S|%d|%d|%d|%d", isVip(player) and 1 or 0, row.day % 7 + 1, canClaim and 1 or 0, isAtShrine(player) and 1 or 0))
end

-- Llamado por el santuario de recompensas al usarlo
function VipDailyReward.onShrineUse(player)
	shrineVisits[player:getId()] = { time = os.time(), pos = player:getPosition() }
	VipDailyReward.sendState(player)
end

-- Entrega los objetos en el buzón. Si algo no cabe, quita lo ya entregado y devuelve false.
local function deliverItems(player, list)
	local inbox = player:getStoreInbox()
	if not inbox then
		return false
	end
	local added = {}
	for _, entry in ipairs(list) do
		local item = inbox:addItem(entry[1], entry[2])
		if not item then
			for _, done in ipairs(added) do
				done:remove()
			end
			return false
		end
		item:setAttribute(ITEM_ATTRIBUTE_STORE, systemTime())
		added[#added + 1] = item
	end
	return true
end

-- Comprueba que la recompensa se puede entregar (sin entregarla todavía)
local function validate(player, reward, choice)
	if reward.type == "items" and not reward.choices[choice] then
		return "Elige una opci\243n v\225lida."
	end
	if reward.type == "exercise" and not EXERCISE_WEAPONS[choice] then
		return "Elige un arma de entrenamiento v\225lida."
	end
	if (reward.type == "xpboost" or reward.type == "chest") and player:getXpBoostTime() > 0 then
		return "Ya tienes un Potenciador de XP activo. Recl\225mala cuando termine; no perder\225s el d\237a."
	end
	return nil
end

-- Entrega la recompensa. Devuelve el texto para el historial o nil si falló.
local function deliver(player, reward, choice)
	if reward.type == "items" then
		local entry = reward.choices[choice]
		if not deliverItems(player, { entry }) then
			return nil
		end
		return string.format("%dx %s", entry[2], ItemType(entry[1]):getName())
	elseif reward.type == "exercise" then
		local itemId = EXERCISE_WEAPONS[choice]
		if not deliverItems(player, { { itemId, EXERCISE_CHARGES } }) then
			return nil
		end
		return string.format("%s (%d cargas)", ItemType(itemId):getName(), EXERCISE_CHARGES)
	elseif reward.type == "prey" then
		player:addPreyCards(reward.amount)
		return string.format("%dx comod\237n de presa", reward.amount)
	elseif reward.type == "tokens" then
		player:setCollectionTokens(player:getCollectionTokens() + reward.amount)
		return string.format("%dx Acceso instant\225neo a recompensas", reward.amount)
	elseif reward.type == "xpboost" then
		player:setXpBoostPercent(50)
		player:setXpBoostTime(reward.minutes * 60)
		return string.format("Potenciador de XP del 50%% durante %d minutos", reward.minutes)
	elseif reward.type == "chest" then
		player:setXpBoostPercent(50)
		player:setXpBoostTime(reward.minutes * 60)
		player:addTibiaCoins(reward.coins)
		player:setCollectionTokens(player:getCollectionTokens() + reward.tokens)
		return string.format("Cofre VIP: Potenciador de XP de %d minutos, %d Tibia Coins y %dx Acceso instant\225neo a recompensas", reward.minutes, reward.coins, reward.tokens)
	end
	return nil
end

local function claim(player, choice)
	if not ensureTable() then
		return sendMessage(player, "Algo sali\243 mal. Int\233ntalo m\225s tarde.")
	end
	if not isVip(player) then
		return sendMessage(player, "Las recompensas VIP son solo para cuentas VIP.")
	end
	if not isAtShrine(player) then
		return sendMessage(player, "Las recompensas VIP solo se reclaman en un santuario de recompensas.")
	end

	local accountId = player:getAccountId()
	local saveCount = GetDailyRewardServerSaveCount()
	local row = readRow(accountId)
	if row.lastClaimSave >= saveCount then
		return sendMessage(player, "Ya reclamaste la recompensa VIP de hoy en esta cuenta.")
	end

	local dayIndex = row.day % 7 + 1
	local reward = REWARDS[dayIndex]
	local invalid = validate(player, reward, choice)
	if invalid then
		return sendMessage(player, invalid)
	end

	-- Reserva atómica del día: solo gana una petición aunque haya varios personajes de la cuenta.
	local token = math.random(1, 2147483646)
	db.query(string.format("INSERT IGNORE INTO `vip_daily_reward` (`account_id`, `day`, `last_claim_save`, `claim_token`) VALUES (%d, 0, -1, 0)", accountId))
	db.query(string.format("UPDATE `vip_daily_reward` SET `last_claim_save` = %d, `claim_token` = %d, `day` = (`day` + 1) %% 7 WHERE `account_id` = %d AND `last_claim_save` < %d AND `day` = %d", saveCount, token, accountId, saveCount, row.day))
	local check = readRow(accountId)
	if check.token ~= token or check.lastClaimSave ~= saveCount then
		return sendMessage(player, "Ya reclamaste la recompensa VIP de hoy en esta cuenta.")
	end

	local description = deliver(player, reward, choice)
	if not description then
		-- No cabía en el buzón: se devuelve la reserva para que pueda reclamarla más tarde.
		db.query(string.format("UPDATE `vip_daily_reward` SET `last_claim_save` = %d, `day` = %d WHERE `account_id` = %d AND `claim_token` = %d", row.lastClaimSave, row.day, accountId, token))
		VipDailyReward.sendState(player)
		return sendMessage(player, "No tienes espacio suficiente en tu buz\243n de la Tienda.")
	end

	DailyReward.insertHistory(player:getGuid(), player:getDayStreak(), string.format("Recompensa VIP d\237a %d: %s.", dayIndex, description))
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[VIP] Recompensa VIP del d\237a %d: %s.", dayIndex, description))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	VipDailyReward.sendState(player)
	sendMessage(player, string.format("\161Recompensa VIP recibida! %s.", description))
end

local opcodeEvent = CreatureEvent("VipDailyRewardOpcode")

function opcodeEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	if buffer == "state" then
		VipDailyReward.sendState(player)
		return
	end
	local choice = buffer:match("^claim:(%d+)$")
	if choice then
		-- Evita spam de peticiones (una cada 2 segundos)
		local now = systemTime()
		local last = player:kv():get("vip-daily-reward-last-request") or 0
		if now - last < 2000 then
			return
		end
		player:kv():set("vip-daily-reward-last-request", now)
		claim(player, tonumber(choice))
	end
end

opcodeEvent:register()

local loginEvent = CreatureEvent("VipDailyRewardLogin")

function loginEvent.onLogin(player)
	player:registerEvent("VipDailyRewardOpcode")
	return true
end

loginEvent:register()

local logoutEvent = CreatureEvent("VipDailyRewardLogout")

function logoutEvent.onLogout(player)
	shrineVisits[player:getId()] = nil
	return true
end

logoutEvent:register()
