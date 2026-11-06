-- RoT scheduled guild wars with gold stakes.
--
-- Guild leaders challenge each other on the website (page guild-wars), which writes rows into
-- `rot_war_challenges`. This script runs the rest:
--   status 0 pending  -> expires (3) if the start time passes without being accepted
--   status 1 accepted -> at start_at both leaders pay the stake from their bank; a `guild_wars` row is
--                        created (status 1) so the engine counts frags and removes skulls; becomes 4
--   status 4 active   -> when the engine ends the war (frag limit or duration), the winner guild's
--                        participants (killed or died in the war) split the pot; becomes 5
--   status 2 rejected, 3 canceled, 5 finished
-- Gold is only moved here on the game server (never on the website), so it can't be overwritten by a save.
-- The engine loads a player's war list at login, so members online when a war starts or ends are
-- disconnected after a warning to reload it.

local CHECK_INTERVAL = 60 * 1000
local KICK_DELAY = 10 * 1000
local DOUBLE_EXP_SECONDS = 3 * 24 * 60 * 60 -- winners' participants get 3 days of double experience
local doubleExpKV = kv.scoped("rot-war-double-exp")

local function grantDoubleExp(playerId)
	local key = "player-" .. playerId
	local now = os.time()
	local current = doubleExpKV:get(key) or 0
	doubleExpKV:set(key, math.max(current, now) + DOUBLE_EXP_SECONDS)
end

local STATUS_PENDING, STATUS_ACCEPTED, STATUS_REJECTED, STATUS_CANCELED, STATUS_ACTIVE, STATUS_FINISHED = 0, 1, 2, 3, 4, 5

local tableReady = false
local function ensureTable()
	if not tableReady then
		tableReady = db.query([[CREATE TABLE IF NOT EXISTS `rot_war_challenges` (
			`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
			`guild1` INT NOT NULL,
			`guild2` INT NOT NULL,
			`name1` VARCHAR(255) NOT NULL,
			`name2` VARCHAR(255) NOT NULL,
			`frags_limit` SMALLINT UNSIGNED NOT NULL,
			`duration_hours` SMALLINT UNSIGNED NOT NULL,
			`start_at` BIGINT NOT NULL,
			`stake` BIGINT UNSIGNED NOT NULL DEFAULT 0,
			`status` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`war_id` INT NOT NULL DEFAULT 0,
			`charged1` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`charged2` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`winner` INT NOT NULL DEFAULT 0,
			`kills1` INT UNSIGNED NOT NULL DEFAULT 0,
			`kills2` INT UNSIGNED NOT NULL DEFAULT 0,
			`created` BIGINT NOT NULL,
			`finished` BIGINT NOT NULL DEFAULT 0,
			`note` VARCHAR(255) NOT NULL DEFAULT '',
			PRIMARY KEY (`id`),
			INDEX `status` (`status`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]) == true
	end
	return tableReady
end

local function broadcast(message)
	Game.broadcastMessage("[Guild War] " .. message, MESSAGE_GAME_HIGHLIGHT)
end

local function queryRows(sql, columns)
	local rows = {}
	local resultId = db.storeQuery(sql)
	if resultId then
		repeat
			local row = {}
			for name, kind in pairs(columns) do
				row[name] = kind == "string" and Result.getString(resultId, name) or Result.getNumber(resultId, name)
			end
			rows[#rows + 1] = row
		until not Result.next(resultId)
		Result.free(resultId)
	end
	return rows
end

local function getPlayerRow(playerId)
	return queryRows("SELECT `name`, `balance` FROM `players` WHERE `id` = " .. playerId, { name = "string", balance = "number" })[1]
end

local function getGuildOwner(guildId)
	local row = queryRows("SELECT `ownerid` FROM `guilds` WHERE `id` = " .. guildId, { ownerid = "number" })[1]
	return row and row.ownerid or nil
end

-- Bank movements work for online players (memory) and offline players (database).
local function addBank(playerId, amount)
	if amount <= 0 then
		return true
	end
	local row = getPlayerRow(playerId)
	if not row then
		return false
	end
	local player = Player(row.name)
	if player then
		player:setBankBalance(player:getBankBalance() + amount)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[Guild War] %d gold has been deposited into your bank account.", amount))
		return true
	end
	return db.query(string.format("UPDATE `players` SET `balance` = `balance` + %d WHERE `id` = %d", amount, playerId))
end

local function removeBank(playerId, amount)
	if amount <= 0 then
		return true
	end
	local row = getPlayerRow(playerId)
	if not row then
		return false
	end
	local player = Player(row.name)
	if player then
		local balance = player:getBankBalance()
		if balance < amount then
			return false
		end
		player:setBankBalance(balance - amount)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[Guild War] %d gold has been taken from your bank account as the war stake.", amount))
		return true
	end
	if row.balance < amount then
		return false
	end
	db.query(string.format("UPDATE `players` SET `balance` = `balance` - %d WHERE `id` = %d AND `balance` >= %d", amount, playerId, amount))
	local after = getPlayerRow(playerId)
	return after ~= nil and after.balance == row.balance - amount
end

-- Disconnect online members of both guilds so their war list is reloaded on login.
local function refreshGuildMembers(guildIds, message)
	local names = {}
	for _, player in ipairs(Game.getPlayers()) do
		local guild = player:getGuild()
		if guild and (guild:getId() == guildIds[1] or guild:getId() == guildIds[2]) then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, message .. " You will be disconnected in 10 seconds to update the war status. Log in again right away.")
			names[#names + 1] = player:getName()
		end
	end
	addEvent(function(playerNames)
		for _, name in ipairs(playerNames) do
			local player = Player(name)
			if player then
				player:remove()
			end
		end
	end, KICK_DELAY, names)
end

local challengeColumns = {
	id = "number", guild1 = "number", guild2 = "number", name1 = "string", name2 = "string",
	frags_limit = "number", duration_hours = "number", start_at = "number", stake = "number",
	status = "number", war_id = "number", charged1 = "number", charged2 = "number",
}

local function setStatus(id, status, extra)
	db.query(string.format("UPDATE `rot_war_challenges` SET `status` = %d%s WHERE `id` = %d", status, extra or "", id))
end

local function cancelChallenge(challenge, reason)
	local owner1, owner2 = getGuildOwner(challenge.guild1), getGuildOwner(challenge.guild2)
	if challenge.charged1 == 1 and owner1 then
		addBank(owner1, challenge.stake)
	end
	if challenge.charged2 == 1 and owner2 then
		addBank(owner2, challenge.stake)
	end
	setStatus(challenge.id, STATUS_CANCELED, ", `finished` = " .. os.time() .. ", `note` = " .. db.escapeString(reason))
	broadcast(string.format("The war between %s and %s was canceled: %s", challenge.name1, challenge.name2, reason))
end

local function startWar(challenge)
	local now = os.time()
	local owner1, owner2 = getGuildOwner(challenge.guild1), getGuildOwner(challenge.guild2)
	if not owner1 or not owner2 then
		cancelChallenge(challenge, "one of the guilds no longer exists.")
		return
	end

	-- Refuse to start while either guild is already in another active war against the same guild.
	local busy = queryRows(string.format("SELECT `id` FROM `guild_wars` WHERE `status` = 1 AND ((`guild1` = %d AND `guild2` = %d) OR (`guild1` = %d AND `guild2` = %d))", challenge.guild1, challenge.guild2, challenge.guild2, challenge.guild1), { id = "number" })
	if #busy > 0 then
		cancelChallenge(challenge, "these guilds are already at war.")
		return
	end

	if challenge.stake > 0 then
		if challenge.charged1 == 0 then
			if not removeBank(owner1, challenge.stake) then
				cancelChallenge(challenge, challenge.name1 .. "'s leader does not have the stake in the bank.")
				return
			end
			challenge.charged1 = 1
			db.query("UPDATE `rot_war_challenges` SET `charged1` = 1 WHERE `id` = " .. challenge.id)
		end
		if challenge.charged2 == 0 then
			if not removeBank(owner2, challenge.stake) then
				cancelChallenge(challenge, challenge.name2 .. "'s leader does not have the stake in the bank.")
				return
			end
			challenge.charged2 = 1
			db.query("UPDATE `rot_war_challenges` SET `charged2` = 1 WHERE `id` = " .. challenge.id)
		end
	end

	local ended = now + challenge.duration_hours * 60 * 60
	if not db.query(string.format("INSERT INTO `guild_wars` (`guild1`, `guild2`, `name1`, `name2`, `status`, `started`, `ended`, `frags_limit`, `payment`, `duration_days`) VALUES (%d, %d, %s, %s, 1, %d, %d, %d, %d, %d)", challenge.guild1, challenge.guild2, db.escapeString(challenge.name1), db.escapeString(challenge.name2), now, ended, challenge.frags_limit, challenge.stake, math.max(1, math.ceil(challenge.duration_hours / 24)))) then
		cancelChallenge(challenge, "the war could not be created.")
		return
	end
	local war = queryRows(string.format("SELECT `id` FROM `guild_wars` WHERE `guild1` = %d AND `guild2` = %d AND `status` = 1 ORDER BY `id` DESC LIMIT 1", challenge.guild1, challenge.guild2), { id = "number" })[1]
	setStatus(challenge.id, STATUS_ACTIVE, ", `war_id` = " .. (war and war.id or 0))

	local pot = challenge.stake * 2
	broadcast(string.format("The war between %s and %s has started! First to %d frags or most frags in %d hours wins%s.", challenge.name1, challenge.name2, challenge.frags_limit, challenge.duration_hours, pot > 0 and string.format(" a pot of %d gold", pot) or ""))
	refreshGuildMembers({ challenge.guild1, challenge.guild2 }, "Your guild war has started!")
end

local function finishWar(challenge)
	local kills = queryRows(string.format("SELECT `killerguild`, COUNT(*) AS `total` FROM `guildwar_kills` WHERE `warid` = %d GROUP BY `killerguild`", challenge.war_id), { killerguild = "number", total = "number" })
	local kills1, kills2 = 0, 0
	for _, row in ipairs(kills) do
		if row.killerguild == challenge.guild1 then
			kills1 = row.total
		elseif row.killerguild == challenge.guild2 then
			kills2 = row.total
		end
	end

	local pot = challenge.stake * 2
	local winner, winnerName = 0, nil
	if kills1 > kills2 then
		winner, winnerName = challenge.guild1, challenge.name1
	elseif kills2 > kills1 then
		winner, winnerName = challenge.guild2, challenge.name2
	end

	if winner == 0 then
		-- Draw: each leader gets the stake back.
		local owner1, owner2 = getGuildOwner(challenge.guild1), getGuildOwner(challenge.guild2)
		if challenge.charged1 == 1 and owner1 then
			addBank(owner1, challenge.stake)
		end
		if challenge.charged2 == 1 and owner2 then
			addBank(owner2, challenge.stake)
		end
		broadcast(string.format("The war between %s and %s ended in a draw (%d - %d).", challenge.name1, challenge.name2, kills1, kills2))
	else
		-- Participants: winner guild members who killed or died in this war.
		local participants = queryRows(string.format([[SELECT DISTINCT p.`id` FROM `players` p
			INNER JOIN `guild_membership` gm ON gm.`player_id` = p.`id` AND gm.`guild_id` = %d
			INNER JOIN `guildwar_kills` k ON k.`warid` = %d AND (k.`killer` = p.`name` OR k.`target` = p.`name`)]], winner, challenge.war_id), { id = "number" })
		if pot > 0 then
			if #participants == 0 then
				local owner = getGuildOwner(winner)
				if owner then
					participants = { { id = owner } }
				end
			end
			local share = math.floor(pot / math.max(1, #participants))
			for _, participant in ipairs(participants) do
				addBank(participant.id, share)
			end
		end
		for _, participant in ipairs(participants) do
			grantDoubleExp(participant.id)
		end
		if pot > 0 then
			broadcast(string.format("%s won the war against %s (%d - %d)! %d gold and 3 days of double experience were given to %d participants.", winnerName, winner == challenge.guild1 and challenge.name2 or challenge.name1, math.max(kills1, kills2), math.min(kills1, kills2), pot, #participants))
		else
			broadcast(string.format("%s won the war against %s (%d - %d)! Its participants get 3 days of double experience.", winnerName, winner == challenge.guild1 and challenge.name2 or challenge.name1, math.max(kills1, kills2), math.min(kills1, kills2)))
		end
	end

	setStatus(challenge.id, STATUS_FINISHED, string.format(", `winner` = %d, `kills1` = %d, `kills2` = %d, `finished` = %d", winner, kills1, kills2, os.time()))
	refreshGuildMembers({ challenge.guild1, challenge.guild2 }, "Your guild war has ended.")
end

local function processChallenges()
	if not ensureTable() then
		return
	end
	local now = os.time()
	local fields = "`id`, `guild1`, `guild2`, `name1`, `name2`, `frags_limit`, `duration_hours`, `start_at`, `stake`, `status`, `war_id`, `charged1`, `charged2`"

	for _, challenge in ipairs(queryRows("SELECT " .. fields .. " FROM `rot_war_challenges` WHERE `status` = " .. STATUS_PENDING .. " AND `start_at` <= " .. now, challengeColumns)) do
		setStatus(challenge.id, STATUS_CANCELED, ", `finished` = " .. now .. ", `note` = 'Not accepted before the start time.'")
	end

	for _, challenge in ipairs(queryRows("SELECT " .. fields .. " FROM `rot_war_challenges` WHERE `status` = " .. STATUS_ACCEPTED .. " AND `start_at` <= " .. now, challengeColumns)) do
		startWar(challenge)
	end

	for _, challenge in ipairs(queryRows("SELECT c.`id`, c.`guild1`, c.`guild2`, c.`name1`, c.`name2`, c.`frags_limit`, c.`duration_hours`, c.`start_at`, c.`stake`, c.`status`, c.`war_id`, c.`charged1`, c.`charged2` FROM `rot_war_challenges` c INNER JOIN `guild_wars` w ON w.`id` = c.`war_id` WHERE c.`status` = " .. STATUS_ACTIVE .. " AND w.`status` <> 1", challengeColumns)) do
		finishWar(challenge)
	end
end

local warStartup = GlobalEvent("RoTGuildWarsStartup")
function warStartup.onStartup()
	ensureTable()
	return true
end
warStartup:register()

local warThink = GlobalEvent("RoTGuildWarsThink")
function warThink.onThink(interval)
	processChallenges()
	return true
end
warThink:interval(CHECK_INTERVAL)
warThink:register()

-- Double experience for war winners.
local function doubleExpRemaining(player)
	local untilTime = doubleExpKV:get("player-" .. player:getGuid()) or 0
	return untilTime - os.time()
end

local warExp = EventCallback("RoTGuildWarDoubleExp")
function warExp.playerOnGainExperience(player, target, exp, rawExp)
	if exp > 0 and doubleExpRemaining(player) > 0 then
		exp = exp * 2
	end
	return exp
end
warExp:register()

local warExpLogin = CreatureEvent("RoTGuildWarDoubleExpLogin")
function warExpLogin.onLogin(player)
	local remaining = doubleExpRemaining(player)
	if remaining > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[Guild War] Victory bonus: double experience for %d more hours.", math.ceil(remaining / 3600)))
	end
	return true
end
warExpLogin:register()
