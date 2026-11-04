-- Bounty hunting (sicariato): a player puts Tibia coins on another player's head for a limited time.
-- The coins are taken on placement (minus a fee that is never refunded). When the target dies, every
-- player that recently damaged them shares the reward equally; if time runs out the placer is refunded.
-- The client (modules/game_bounty) shows the wanted list over the game screen via extended opcode 121.
local Core = BountyCore
local config = Core.config
local OPCODE = 121

Bounty = Bounty or {}
local B = Bounty
B.tableReady = false
B.lastRequest = {}

local function message(player, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[Recompensas] " .. text)
	player:sendExtendedOpcode(OPCODE, "M|" .. text)
end

local function ensureTable()
	if B.tableReady then
		return true
	end
	B.tableReady = db.query("CREATE TABLE IF NOT EXISTS `bounties` (`id` INT NOT NULL AUTO_INCREMENT, `target_id` INT NOT NULL, `placer_id` INT NOT NULL, `placer_account` INT NOT NULL, `amount` INT NOT NULL, `fee` INT NOT NULL, `pot` INT NOT NULL, `created_at` INT NOT NULL, `expires_at` INT NOT NULL, `status` TINYINT NOT NULL DEFAULT 0, `closed_at` INT NOT NULL DEFAULT 0, `paid_to` VARCHAR(255) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY `active_target` (`status`, `target_id`), KEY `active_expiry` (`status`, `expires_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4") == true
	return B.tableReady
end

local STATUS_ACTIVE, STATUS_PAID, STATUS_REFUNDED = 0, 1, 2

-- Credits coins to an account whether its characters are online or not (coins live in the database).
local function creditAccount(accountId, coins, onlinePlayer, detail)
	if coins <= 0 then
		return
	end
	if onlinePlayer and onlinePlayer:getAccountId() == accountId then
		if onlinePlayer:addTibiaCoins(coins) then
			return
		end
	end
	db.query(string.format("UPDATE `accounts` SET `coins` = `coins` + %d WHERE `id` = %d", coins, accountId))
	logger.info("[Bounty] {} coins credited to account {} ({})", coins, accountId, detail)
end

local function activeRows(targetId)
	local rows = {}
	local query = "SELECT b.`id`, b.`target_id`, b.`placer_account`, b.`pot`, b.`expires_at`, p.`name`, p.`level`, p.`vocation` FROM `bounties` b INNER JOIN `players` p ON p.`id` = b.`target_id` WHERE b.`status` = 0"
	if targetId then
		query = query .. string.format(" AND b.`target_id` = %d", targetId)
	end
	local result = db.storeQuery(query)
	if not result then
		return rows
	end
	repeat
		local vocation = Vocation(Result.getNumber(result, "vocation"))
		rows[#rows + 1] = {
			id = Result.getNumber(result, "id"),
			targetId = Result.getNumber(result, "target_id"),
			placerAccount = Result.getNumber(result, "placer_account"),
			pot = Result.getNumber(result, "pot"),
			expiresAt = Result.getNumber(result, "expires_at"),
			targetName = Result.getString(result, "name"),
			level = Result.getNumber(result, "level"),
			vocation = vocation and vocation:getName() or "",
		}
	until not Result.next(result)
	Result.free(result)
	return rows
end

function B.sendList(player, cachedPayload)
	player:sendExtendedOpcode(OPCODE, cachedPayload or Core.encodeList(Core.wantedList(activeRows(), os.time()), os.time()))
end

function B.broadcastList()
	local payload = Core.encodeList(Core.wantedList(activeRows(), os.time()), os.time())
	for _, player in ipairs(Game.getPlayers()) do
		player:sendExtendedOpcode(OPCODE, payload)
	end
end

local function countActiveByPlacer(accountId)
	local result = db.storeQuery(string.format("SELECT COUNT(*) AS `total` FROM `bounties` WHERE `status` = 0 AND `placer_account` = %d", accountId))
	if not result then
		return 0
	end
	local total = Result.getNumber(result, "total")
	Result.free(result)
	return total
end

local function totalCoins(player)
	return (player:getTibiaCoins() or 0) + (player:getTransferableCoins() or 0)
end

function B.place(player, targetName, amount, hours)
	if not ensureTable() then
		message(player, "El sistema no est\225 disponible.")
		return false
	end
	targetName = (targetName or ""):trim()
	local result = db.storeQuery(string.format("SELECT `id`, `name`, `account_id`, `level`, `group_id` FROM `players` WHERE `name` = %s", db.escapeString(targetName)))
	local target = nil
	if result then
		target = {
			id = Result.getNumber(result, "id"),
			name = Result.getString(result, "name"),
			accountId = Result.getNumber(result, "account_id"),
			level = Result.getNumber(result, "level"),
			staff = Result.getNumber(result, "group_id") > 1,
		}
		Result.free(result)
	end

	local ok, reason = Core.validatePlacement({
		amount = amount,
		hours = hours,
		placerCoins = totalCoins(player),
		placerAccount = player:getAccountId(),
		targetAccount = target and target.accountId,
		targetLevel = target and target.level,
		targetIsStaff = target and target.staff,
		activeByPlacer = countActiveByPlacer(player:getAccountId()),
	})
	if not ok then
		message(player, reason)
		return false
	end

	if not player:removeTransferableAndTibiaCoins(amount) then
		message(player, "No se pudieron descontar las Tibia coins.")
		return false
	end
	local fee, pot = Core.fee(amount)
	local now = os.time()
	local inserted = db.query(string.format("INSERT INTO `bounties` (`target_id`, `placer_id`, `placer_account`, `amount`, `fee`, `pot`, `created_at`, `expires_at`) VALUES (%d, %d, %d, %d, %d, %d, %d, %d)", target.id, player:getGuid(), player:getAccountId(), amount, fee, pot, now, now + hours * 3600))
	if not inserted then
		creditAccount(player:getAccountId(), amount, player, "bounty insert failed")
		message(player, "No se pudo registrar la recompensa; se devolvieron tus coins.")
		return false
	end

	logger.info("[Bounty] {} placed {} coins ({} pot) on {} for {}h", player:getName(), amount, pot, target.name, hours)
	message(player, string.format("Recompensa de %d Tibia coins por %s durante %dh (comisi\243n %d, se reparten %d).", amount, target.name, hours, fee, pot))
	local targetPlayer = Player(target.id)
	if targetPlayer then
		targetPlayer:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[Recompensas] \161Hay una recompensa de %d Tibia coins por tu cabeza!", pot))
	end
	Game.broadcastMessage(string.format("[Recompensas] Nueva recompensa: %d Tibia coins por %s.", pot, target.name), MESSAGE_STATUS)
	B.broadcastList()
	return true
end

local function resolveAttacker(creatureId)
	local creature = Creature(creatureId)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature:getPlayer()
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master:getPlayer()
	end
	return nil
end

function B.onTargetDeath(player)
	if not B.tableReady then
		return
	end
	local rows = activeRows(player:getGuid())
	if #rows == 0 then
		return
	end
	-- Deaths in PvP arenas cost nothing, so they never pay a bounty
	local tile = Tile(player:getPosition())
	if tile and tile:hasFlag(TILESTATE_PVPZONE) then
		return
	end

	local now, nowMs = os.time(), systemTime()
	local excluded, pot = {}, 0
	local valid = {}
	for _, row in ipairs(rows) do
		if row.expiresAt > now then
			excluded[row.placerAccount] = true
			pot = pot + row.pot
			valid[#valid + 1] = row
		end
	end
	if #valid == 0 then
		return
	end

	local attackers, byPlayer = {}, {}
	for creatureId, entry in pairs(player:getDamageMap() or {}) do
		local attacker = resolveAttacker(creatureId)
		if attacker then
			local guid = attacker:getGuid()
			local data = byPlayer[guid]
			if not data then
				data = { id = guid, accountId = attacker:getAccountId(), ip = attacker:getIp(), damage = 0, lastHit = 0, isPlayer = true, name = attacker:getName() }
				byPlayer[guid] = data
				attackers[#attackers + 1] = data
			end
			data.damage = data.damage + (entry.total or 0)
			data.lastHit = math.max(data.lastHit, entry.ticks or 0)
		end
	end

	local killers = Core.eligibleKillers(attackers, { accountId = player:getAccountId(), ip = player:getIp() }, excluded, nowMs)
	if #killers == 0 then
		return -- died to monsters or to excluded players: the bounty stays active
	end

	local shares = Core.split(pot, killers)
	local names = {}
	for _, killer in ipairs(killers) do
		names[#names + 1] = killer.name
	end
	local paidTo = table.concat(names, ", ")
	for _, row in ipairs(valid) do
		db.query(string.format("UPDATE `bounties` SET `status` = %d, `closed_at` = %d, `paid_to` = %s WHERE `id` = %d AND `status` = 0", STATUS_PAID, now, db.escapeString(paidTo:sub(1, 255)), row.id))
	end
	for _, killer in ipairs(killers) do
		local share = shares[killer.id] or 0
		local online = Player(killer.id)
		creditAccount(killer.accountId, share, online, "bounty on " .. player:getName())
		if online then
			message(online, string.format("Cobraste %d Tibia coins por cazar a %s.", share, player:getName()))
		end
	end
	logger.info("[Bounty] {} hunted, {} coins split between {}", player:getName(), pot, paidTo)
	Game.broadcastMessage(string.format("[Recompensas] %s fue cazado. %d Tibia coins repartidas entre: %s.", player:getName(), pot, paidTo), MESSAGE_STATUS)
	B.broadcastList()
end

function B.expire()
	if not B.tableReady then
		return
	end
	local now = os.time()
	local result = db.storeQuery(string.format("SELECT b.`id`, b.`placer_id`, b.`placer_account`, b.`pot`, p.`name` FROM `bounties` b INNER JOIN `players` p ON p.`id` = b.`target_id` WHERE b.`status` = 0 AND b.`expires_at` <= %d", now))
	if not result then
		return
	end
	local expired = {}
	repeat
		expired[#expired + 1] = {
			id = Result.getNumber(result, "id"),
			placerId = Result.getNumber(result, "placer_id"),
			placerAccount = Result.getNumber(result, "placer_account"),
			pot = Result.getNumber(result, "pot"),
			targetName = Result.getString(result, "name"),
		}
	until not Result.next(result)
	Result.free(result)

	for _, row in ipairs(expired) do
		-- Close first so a crash between the two steps can never refund twice
		db.query(string.format("UPDATE `bounties` SET `status` = %d, `closed_at` = %d WHERE `id` = %d AND `status` = 0", STATUS_REFUNDED, now, row.id))
		local placer = Player(row.placerId)
		creditAccount(row.placerAccount, row.pot, placer, "bounty refund")
		if placer then
			message(placer, string.format("Tu recompensa por %s expir\243 sin cobrarse. Se te devolvieron %d Tibia coins.", row.targetName, row.pot))
		end
	end
	B.broadcastList()
end

-- -----------------------------------------------------------------------------------------------------
-- Events
-- -----------------------------------------------------------------------------------------------------
local death = CreatureEvent("BountyDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, unjustified, mostDamageUnjustified)
	local player = creature:getPlayer()
	if player then
		B.onTargetDeath(player)
	end
	return true
end
death:register()

local opcode = CreatureEvent("BountyOpcode")
function opcode.onExtendedOpcode(player, opcodeId, buffer)
	if opcodeId ~= OPCODE then
		return
	end
	local now = systemTime()
	if now - (B.lastRequest[player:getId()] or 0) < 1000 then
		return
	end
	B.lastRequest[player:getId()] = now

	if buffer == "list" then
		B.sendList(player)
		return
	end
	local name, amount, hours = buffer:match("^place|([^|]+)|(%d+)|(%d+)$")
	if name then
		B.place(player, name, tonumber(amount), tonumber(hours))
	end
end
opcode:register()

local login = CreatureEvent("BountyLogin")
function login.onLogin(player)
	player:registerEvent("BountyDeath")
	player:registerEvent("BountyOpcode")
	if B.tableReady then
		B.sendList(player)
	end
	return true
end
login:register()

local logout = CreatureEvent("BountyLogout")
function logout.onLogout(player)
	B.lastRequest[player:getId()] = nil
	return true
end
logout:register()

local startup = GlobalEvent("BountyStartup")
function startup.onStartup()
	if ensureTable() then
		B.expire()
		logger.info("[Bounty] Ready, {} active bounties", #activeRows())
	else
		logger.error("[Bounty] Could not create the bounties table")
	end
	return true
end
startup:register()

-- Expire every 30s; the full list is re-sent every minute so clients stay in sync
local tick = GlobalEvent("BountyTick")
local tickCount = 0
function tick.onThink(interval)
	tickCount = tickCount + 1
	B.expire()
	if tickCount % 2 == 0 then
		B.broadcastList()
	end
	return true
end
tick:interval(30 * 1000)
tick:register()

-- -----------------------------------------------------------------------------------------------------
-- Commands (same actions as the client window)
-- -----------------------------------------------------------------------------------------------------
local place = TalkAction("!recompensa")
function place.onSay(player, words, param)
	local name, amount, hours = (param or ""):match("^%s*([^,]+),%s*(%d+)%s*,?%s*(%d*)%s*$")
	if not name then
		message(player, string.format("Uso: !recompensa nombre, monto, horas (horas: %s). Monto entre %d y %d coins; comisi\243n %d%%.", table.concat(config.durations, "/"), config.minReward, config.maxReward, config.feePercent))
		return true
	end
	B.place(player, name, tonumber(amount), tonumber(hours ~= "" and hours or "24"))
	return true
end
place:separator(" ")
place:groupType("normal")
place:register()

local wanted = TalkAction("!buscados")
function wanted.onSay(player, words, param)
	local list = Core.wantedList(activeRows(), os.time())
	local lines = { "M\225s buscados:" }
	if #list == 0 then
		lines[#lines + 1] = "No hay recompensas activas."
	end
	for index, entry in ipairs(list) do
		lines[#lines + 1] = string.format("%d. %s (nivel %d) - %d coins - %s", index, entry.name, entry.level, entry.reward, Core.formatTime(entry.expiresAt - os.time()))
	end
	player:showTextDialog(2854, table.concat(lines, "\n"))
	return true
end
wanted:separator(" ")
wanted:groupType("normal")
wanted:register()
