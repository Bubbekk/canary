-- Fidelidad VIP: días VIP acumulados por CUENTA, cofre cada 30 días VIP,
-- montura exclusiva a los 90 días y mensaje de bienvenida VIP al conectarse.
--
-- Un "día VIP" cuenta como máximo una vez por día natural (UTC) y solo si la cuenta es VIP
-- y alguno de sus personajes se conecta (o sigue conectado) ese día.
-- Todo se guarda al instante en MySQL (tabla `vip_loyalty`) con actualizaciones condicionales,
-- de modo que ni varios personajes, ni reconexiones, ni reinicios permiten cobrar dos veces.
-- Los textos usan escapes Latin-1 (\237 = í, etc.) porque el cliente trabaja en cp1252.

local config = {
	chestEveryDays = 30,
	-- { itemId, cantidad } enviados al buzón de la Tienda
	chestItems = {
		{ 236, 50 }, -- strong health potion
		{ 237, 50 }, -- strong mana potion
		{ 7642, 25 }, -- great spirit potion
	},
	chestCoins = 25,
	exclusiveMountId = 224, -- Dawnbringer Pegasus: no se vende en la Tienda ni se obtiene en misiones
	exclusiveMountName = "Dawnbringer Pegasus",
	exclusiveMountDays = 90,
	checkInterval = 30 * 60 * 1000, -- revisión periódica para jugadores conectados al cambiar de día
}

local tableReady = false

local function ensureTable()
	if not tableReady then
		tableReady = db.query("CREATE TABLE IF NOT EXISTS `vip_loyalty` (`account_id` INT UNSIGNED NOT NULL, `vip_days` INT UNSIGNED NOT NULL DEFAULT 0, `last_counted_day` INT NOT NULL DEFAULT 0, `chests_given` INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4") == true
	end
	return tableReady
end

local function readRow(accountId)
	local resultId = db.storeQuery("SELECT `vip_days`, `chests_given` FROM `vip_loyalty` WHERE `account_id` = " .. accountId)
	if not resultId then
		return nil
	end
	local row = {
		vipDays = Result.getNumber(resultId, "vip_days") or 0,
		chestsGiven = Result.getNumber(resultId, "chests_given") or 0,
	}
	Result.free(resultId)
	return row
end

local function isVipEnabled(player)
	return configManager.getBoolean(configKeys.VIP_SYSTEM_ENABLED) and player:isVip()
end

-- Suma un día VIP si aún no se contó hoy. Devuelve la fila actualizada o nil si la BD falla.
local function countVipDay(accountId)
	local today = math.floor(os.time() / 86400)
	if not db.query(string.format("INSERT IGNORE INTO `vip_loyalty` (`account_id`, `vip_days`, `last_counted_day`, `chests_given`) VALUES (%d, 0, 0, 0)", accountId)) then
		return nil
	end
	if not db.query(string.format("UPDATE `vip_loyalty` SET `vip_days` = `vip_days` + 1, `last_counted_day` = %d WHERE `account_id` = %d AND `last_counted_day` < %d", today, accountId, today)) then
		return nil
	end
	return readRow(accountId)
end

-- Entrega UN cofre pendiente. Primero reserva el cofre en la BD (solo si nadie lo reservó antes),
-- después entrega; si la entrega falla, se devuelve la reserva para intentarlo más tarde.
local function deliverChest(player, accountId, row)
	local due = math.floor(row.vipDays / config.chestEveryDays)
	if due <= row.chestsGiven then
		return false
	end

	local expected = row.chestsGiven
	if not db.query(string.format("UPDATE `vip_loyalty` SET `chests_given` = `chests_given` + 1 WHERE `account_id` = %d AND `chests_given` = %d", accountId, expected)) then
		return false
	end
	local check = readRow(accountId)
	if not check or check.chestsGiven ~= expected + 1 then
		return false
	end

	local inbox = player:getStoreInbox()
	local added = {}
	local ok = inbox ~= nil
	if ok then
		for _, entry in ipairs(config.chestItems) do
			local item = inbox:addItem(entry[1], entry[2])
			if not item then
				ok = false
				break
			end
			item:setAttribute(ITEM_ATTRIBUTE_STORE, systemTime())
			added[#added + 1] = item
		end
	end

	if not ok then
		for _, item in ipairs(added) do
			item:remove()
		end
		db.query(string.format("UPDATE `vip_loyalty` SET `chests_given` = `chests_given` - 1 WHERE `account_id` = %d AND `chests_given` = %d", accountId, expected + 1))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[VIP] No hay espacio en tu buz\243n de la Tienda para tu cofre VIP. Libera espacio y se entregar\225 autom\225ticamente.")
		return false
	end

	if config.chestCoins > 0 then
		player:addTibiaCoins(config.chestCoins)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[VIP] \161Recibiste tu cofre VIP por %d d\237as VIP! Revisa tu buz\243n de la Tienda (pociones) y tus Tibia Coins (+%d).", (expected + 1) * config.chestEveryDays, config.chestCoins))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	return true
end

local function grantExclusiveMount(player, row)
	if row.vipDays < config.exclusiveMountDays or player:hasMount(config.exclusiveMountId) then
		return
	end
	player:addMount(config.exclusiveMountId)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[VIP] \161Gracias por %d d\237as VIP! Desbloqueaste la montura exclusiva %s.", config.exclusiveMountDays, config.exclusiveMountName))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_RED)
end

local function processPlayer(player, isLogin)
	if not isVipEnabled(player) or not ensureTable() then
		return
	end

	local accountId = player:getAccountId()
	local row = countVipDay(accountId)
	if not row then
		return
	end

	-- Puede haber más de un cofre pendiente (p. ej. tras un fallo de entrega); se entregan uno a uno
	for _ = 1, 3 do
		if not deliverChest(player, accountId, row) then
			break
		end
		row = readRow(accountId) or row
	end

	grantExclusiveMount(player, row)

	if isLogin then
		local nextChest = config.chestEveryDays - (row.vipDays % config.chestEveryDays)
		local vipDays = player:getVipDays()
		local remainingText = vipDays >= 1 and string.format("%d d\237a(s)", vipDays) or "menos de 1 d\237a"
		local lines = {
			string.format("[VIP] \161Bienvenido, %s! Tu cuenta es VIP: te queda(n) %s.", player:getName(), remainingText),
			string.format("[VIP] D\237as VIP acumulados: %d. Pr\243ximo cofre VIP en %d d\237a(s).", row.vipDays, nextChest),
		}
		if row.vipDays < config.exclusiveMountDays then
			lines[#lines + 1] = string.format("[VIP] Montura exclusiva %s en %d d\237a(s) VIP.", config.exclusiveMountName, config.exclusiveMountDays - row.vipDays)
		end
		for _, line in ipairs(lines) do
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, line)
		end
		player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_BLUE)
	end
end

local loyaltyLogin = CreatureEvent("VipLoyaltyLogin")

function loyaltyLogin.onLogin(player)
	local playerId = player:getId()
	-- Pequeño retraso para que el mensaje llegue después de los de bienvenida
	addEvent(function()
		local target = Player(playerId)
		if target then
			processPlayer(target, true)
		end
	end, 2000)
	return true
end

loyaltyLogin:register()

local loyaltyCheck = GlobalEvent("VipLoyaltyCheck")

function loyaltyCheck.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		processPlayer(player, false)
	end
	return true
end

loyaltyCheck:interval(config.checkInterval)
loyaltyCheck:register()
