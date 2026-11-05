-- Battle Royale ranked mode (Tibia mechanics only).
-- Players queue with !br, play at an equalized level with a fixed kit and floor loot inside a generated
-- arena whose safe zone shrinks, and earn a seasonal rating. Their real character is snapshotted on entry
-- and restored on exit (also after a crash or disconnect, on the next login). Rules live in
-- data/libs/systems/battle_royale_core.lua.
local Core = BattleRoyaleCore
local config = Core.config

-- Hand-made arena on the map: the area connected to ARENA.start (see buildArena). Tiles are PvP and no-logout.
local ARENA = {
	start = Position(1121, 1185, 9),
	maxSearch = 250, -- tiles from the start point, so a map mistake cannot flood the whole floor
	center = Position(1121, 1185, 9), -- recalculated from the map area at startup
	radius = config.arenaRadius,
	lootCount = 660,
	monsters = { "Dragon", "Orc Warlord", "Giant Spider", "Hero", "Warlock", "Dragon Lord" },
	monsterCount = 100,
}

local HOLDER_ITEM = 2854 -- backpack that keeps the real equipment in the inbox while playing
local HOLDER_ATTR = "battleRoyaleHolder"
local SLOT_ATTR = "battleRoyaleSlot"
local KV_SCOPE = "battle-royale"
local ALLOW_SAME_IP = true -- set to false on a public server to block multi-clienting in a match

local LOOT_TIERS = {
	{
		weight = 60,
		items = {
			{ "plate armor", 1 },
			{ "plate legs", 1 },
			{ "steel helmet", 1 },
			{ "dwarven shield", 1 },
			{ "strong health potion", 10 },
			{ "strong mana potion", 15 },
			{ "great fireball rune", 15 },
			{ "intense healing rune", 5 },
		},
	},
	{
		weight = 30,
		items = {
			{ "crown armor", 1 },
			{ "crown legs", 1 },
			{ "crown helmet", 1 },
			{ "crown shield", 1 },
			{ "great health potion", 15 },
			{ "great mana potion", 20 },
			{ "sudden death rune", 10 },
			{ "ultimate healing rune", 5 },
			{ "avalanche rune", 15 },
		},
	},
	{
		weight = 10,
		items = {
			{ "magic plate armor", 1 },
			{ "golden legs", 1 },
			{ "demon shield", 1 },
			{ "boots of haste", 1 },
			{ "royal helmet", 1 },
			{ "ultimate health potion", 10 },
			{ "great spirit potion", 15 },
		},
	},
}

-- Starting kit per base vocation, besides the backpack
local KITS = {
	-- Sorcerer / druid: mana and offensive runes only (they heal with spells)
	[1] = { { "wand of inferno", 1, CONST_SLOT_LEFT }, { "great mana potion", 100 }, { "ultimate mana potion", 30 }, { "sudden death rune", 30 } },
	[2] = { { "underworld rod", 1, CONST_SLOT_LEFT }, { "great mana potion", 100 }, { "ultimate mana potion", 30 }, { "avalanche rune", 30 } },
	-- Paladin: spirit potions restore both, plus ammunition
	[3] = { { "assassin star", 100, CONST_SLOT_LEFT }, { "great spirit potion", 60 }, { "ultimate spirit potion", 15 } },
	-- Knight: health only, no mana
	[4] = { { "fire sword", 1, CONST_SLOT_LEFT }, { "great health potion", 80 }, { "ultimate health potion", 20 } },
	-- Monk
	[9] = { { "great spirit potion", 60 }, { "great health potion", 40 } },
}

local CLEARED_CONDITIONS = { CONDITION_POISON, CONDITION_FIRE, CONDITION_ENERGY, CONDITION_BLEEDING, CONDITION_PARALYZE, CONDITION_DROWN, CONDITION_FREEZING, CONDITION_DAZZLED, CONDITION_CURSED, CONDITION_INFIGHT, CONDITION_HASTE, CONDITION_INVISIBLE, CONDITION_MANASHIELD }

local SEASON_REWARDS = {
	silver = { title = "Gladiador de Plata" },
	gold = { title = "Gladiador de Oro", outfit = { male = 885, female = 884 } },
	platinum = { title = "Gladiador de Platino", outfit = { male = 885, female = 884 }, addon = 1 },
	diamond = { title = "Gladiador de Diamante", outfit = { male = 885, female = 884 }, addon = 3 },
}

BattleRoyale = BattleRoyale or {}
local BR = BattleRoyale

BR.state = "idle" -- idle, countdown, running, ending, disabled
BR.queue = {} -- [guid] = ip
BR.match = nil
BR.arenaReady = false
BR.resolved = nil
BR.tableReady = false

local function say(player, text, messageType)
	player:sendTextMessage(messageType or MESSAGE_EVENT_ADVANCE, "[Battle Royale] " .. text)
end

local function broadcastQueue(text)
	for guid in pairs(BR.queue) do
		local player = Player(guid)
		if player then
			say(player, text)
		end
	end
end

local function broadcastMatch(text, messageType)
	if not BR.match then
		return
	end
	for guid, entry in pairs(BR.match.players) do
		if entry.alive then
			local player = Player(guid)
			if player then
				say(player, text, messageType)
			end
		end
	end
end

local function queueSize()
	local count = 0
	for _ in pairs(BR.queue) do
		count = count + 1
	end
	return count
end

local function isArenaPosition(position)
	return position.z == ARENA.center.z and BR.arenaTiles ~= nil and BR.arenaTiles[position.x * 65536 + position.y] == true
end

-- ---------------------------------------------------------------------------------------------------------
-- Database (ratings per season, match log and pending season rewards)
-- ---------------------------------------------------------------------------------------------------------
local function ensureTables()
	if BR.tableReady then
		return true
	end
	local ok = db.query("CREATE TABLE IF NOT EXISTS `battle_royale_ratings` (`player_id` INT NOT NULL, `season` INT NOT NULL, `rating` INT NOT NULL DEFAULT 1000, `matches` INT NOT NULL DEFAULT 0, `wins` INT NOT NULL DEFAULT 0, `kills` INT NOT NULL DEFAULT 0, `best_rating` INT NOT NULL DEFAULT 1000, `score` INT NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`, `season`), KEY `season_rating` (`season`, `rating`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
		and db.query("CREATE TABLE IF NOT EXISTS `battle_royale_matches` (`id` INT NOT NULL AUTO_INCREMENT, `season` INT NOT NULL, `started_at` INT NOT NULL, `ended_at` INT NOT NULL, `players` INT NOT NULL, `ranked` TINYINT NOT NULL DEFAULT 0, `winner_id` INT NOT NULL DEFAULT 0, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
		and db.query("CREATE TABLE IF NOT EXISTS `battle_royale_rewards` (`player_id` INT NOT NULL, `season` INT NOT NULL, `league` VARCHAR(16) NOT NULL, `claimed` TINYINT NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`, `season`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
		and db.query("CREATE TABLE IF NOT EXISTS `battle_royale_meta` (`key` VARCHAR(32) NOT NULL, `value` INT NOT NULL, PRIMARY KEY (`key`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
	BR.tableReady = ok == true
	return BR.tableReady
end

local function currentSeason()
	return Core.seasonKey(os.time())
end

function BR.getRating(guid, season)
	season = season or currentSeason()
	local result = db.storeQuery(string.format("SELECT `rating`, `matches`, `wins`, `kills`, `best_rating`, `score` FROM `battle_royale_ratings` WHERE `player_id` = %d AND `season` = %d", guid, season))
	if not result then
		return { rating = config.startRating, matches = 0, wins = 0, kills = 0, best = config.startRating, score = 0 }
	end
	local row = {
		rating = Result.getNumber(result, "rating"),
		matches = Result.getNumber(result, "matches"),
		wins = Result.getNumber(result, "wins"),
		kills = Result.getNumber(result, "kills"),
		best = Result.getNumber(result, "best_rating"),
		score = Result.getNumber(result, "score"),
	}
	Result.free(result)
	return row
end

local function saveRating(guid, season, row)
	db.query(string.format("INSERT INTO `battle_royale_ratings` (`player_id`, `season`, `rating`, `matches`, `wins`, `kills`, `best_rating`, `score`) VALUES (%d, %d, %d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `rating` = VALUES(`rating`), `matches` = VALUES(`matches`), `wins` = VALUES(`wins`), `kills` = VALUES(`kills`), `best_rating` = VALUES(`best_rating`), `score` = VALUES(`score`)", guid, season, row.rating, row.matches, row.wins, row.kills, row.best, row.score))
end

-- Closes the stored season when the month changed: every player with enough matches gets the reward
-- of the league they finished in, claimed on their next login.
local function rolloverSeason()
	local season = currentSeason()
	local result = db.storeQuery("SELECT `value` FROM `battle_royale_meta` WHERE `key` = 'season'")
	local stored = nil
	if result then
		stored = Result.getNumber(result, "value")
		Result.free(result)
	end
	if stored == season then
		return
	end
	if stored then
		local rows = db.storeQuery(string.format("SELECT `player_id`, `rating`, `matches` FROM `battle_royale_ratings` WHERE `season` = %d", stored))
		local granted = 0
		if rows then
			repeat
				local matches = Result.getNumber(rows, "matches")
				if matches >= config.minMatchesForReward then
					local league = Core.leagueFor(Result.getNumber(rows, "rating"))
					if SEASON_REWARDS[league.id] then
						db.query(string.format("INSERT IGNORE INTO `battle_royale_rewards` (`player_id`, `season`, `league`) VALUES (%d, %d, %s)", Result.getNumber(rows, "player_id"), stored, db.escapeString(league.id)))
						granted = granted + 1
					end
				end
			until not Result.next(rows)
			Result.free(rows)
		end
		logger.info("[BattleRoyale] Season {} closed, {} rewards granted", stored, granted)
	end
	db.query(string.format("INSERT INTO `battle_royale_meta` (`key`, `value`) VALUES ('season', %d) ON DUPLICATE KEY UPDATE `value` = %d", season, season))
end

local function claimRewards(player)
	local result = db.storeQuery(string.format("SELECT `season`, `league` FROM `battle_royale_rewards` WHERE `player_id` = %d AND `claimed` = 0", player:getGuid()))
	if not result then
		return
	end
	repeat
		local season = Result.getNumber(result, "season")
		local leagueId = Result.getString(result, "league")
		local reward = SEASON_REWARDS[leagueId]
		-- Mark first so a failure never grants the reward twice
		db.query(string.format("UPDATE `battle_royale_rewards` SET `claimed` = 1 WHERE `player_id` = %d AND `season` = %d", player:getGuid(), season))
		if reward then
			if reward.outfit then
				local lookType = player:getSex() == PLAYERSEX_FEMALE and reward.outfit.female or reward.outfit.male
				player:addOutfit(lookType)
				if reward.addon then
					player:addOutfitAddon(lookType, reward.addon)
				end
			end
			player:kv():scoped(KV_SCOPE):set("title", reward.title)
			local leagueName = leagueId
			for _, league in ipairs(Core.leagues) do
				if league.id == leagueId then
					leagueName = league.name
				end
			end
			say(player, string.format("Temporada %d terminada: recibiste las recompensas de la liga %s (%s).", season, leagueName, reward.title))
		end
	until not Result.next(result)
	Result.free(result)
end

-- ---------------------------------------------------------------------------------------------------------
-- Arena
-- ---------------------------------------------------------------------------------------------------------
local function pickItem(candidates, predicate)
	for _, id in ipairs(candidates) do
		local itemType = ItemType(id)
		if itemType and itemType:getId() ~= 0 and predicate(itemType) then
			return id
		end
	end
	return nil
end

local function resolveItems()
	local resolved = { loot = {}, kits = {} }
	local missing = {}
	local function resolve(name)
		local itemType = ItemType(name)
		if not itemType or itemType:getId() == 0 then
			missing[#missing + 1] = name
			return nil
		end
		return itemType:getId()
	end

	for _, tier in ipairs(LOOT_TIERS) do
		local items = {}
		for _, entry in ipairs(tier.items) do
			local id = resolve(entry[1])
			if id then
				items[#items + 1] = { id, entry[2] }
			end
		end
		resolved.loot[#resolved.loot + 1] = { weight = tier.weight, items = items }
	end
	for vocation, kit in pairs(KITS) do
		local items = {}
		for _, entry in ipairs(kit) do
			local id = resolve(entry[1])
			if id then
				items[#items + 1] = { id, entry[2], entry[3] }
			end
		end
		resolved.kits[vocation] = items
	end
	if #missing > 0 then
		logger.warn("[BattleRoyale] Unknown items skipped: {}", table.concat(missing, ", "))
	end
	return resolved
end

-- The arena is the hand-made map area that contains ARENA.start: every tile reachable from it (walls
-- included) is part of the arena. Its bounding box sets the centre and the radius of the shrinking zone.
local function buildArena()
	local start = ARENA.start
	if not Tile(start) or not Tile(start):getGround() then
		logger.error("[BattleRoyale] Arena start ({}, {}, {}) has no ground, mode disabled", start.x, start.y, start.z)
		return false
	end

	local tiles, queue, head = {}, { { start.x, start.y } }, 1
	local minX, maxX, minY, maxY = start.x, start.x, start.y, start.y
	local count, limit = 0, ARENA.maxSearch
	tiles[start.x * 65536 + start.y] = true
	while head <= #queue do
		local x, y = queue[head][1], queue[head][2]
		head = head + 1
		count = count + 1
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minY, maxY = math.min(minY, y), math.max(maxY, y)
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local nx, ny = x + d[1], y + d[2]
			local key = nx * 65536 + ny
			if not tiles[key] and math.abs(nx - start.x) <= limit and math.abs(ny - start.y) <= limit then
				local tile = Tile(nx, ny, start.z)
				if tile and tile:getGround() then
					tiles[key] = true
					queue[#queue + 1] = { nx, ny }
				end
			end
		end
	end

	-- Remember what the map put on every tile, so the cleanup between matches never removes decoration
	local original = {}
	local open = 0
	for key in pairs(tiles) do
		local x, y = math.floor(key / 65536), key % 65536
		local tile = Tile(x, y, start.z)
		tile:setZoneFlag(TILESTATE_PVPZONE, true)
		tile:setZoneFlag(TILESTATE_NOLOGOUT, true)
		local ids = {}
		for _, item in ipairs(tile:getItems() or {}) do
			ids[item:getId()] = (ids[item:getId()] or 0) + 1
		end
		original[key] = ids
		if not tile:hasFlag(TILESTATE_BLOCKSOLID) then
			open = open + 1
		end
	end
	if open == 0 then
		logger.error("[BattleRoyale] Arena has no walkable tiles, mode disabled")
		return false
	end

	BR.arenaTiles = tiles
	BR.arenaOriginal = original
	ARENA.center = Position(math.floor((minX + maxX) / 2), math.floor((minY + maxY) / 2), start.z)
	ARENA.radius = math.max(math.ceil((maxX - minX) / 2), math.ceil((maxY - minY) / 2))

	-- The zone phases are tuned for config.arenaRadius: scale them to the real size of the map area
	local scale = ARENA.radius / config.arenaRadius
	for _, phase in ipairs(config.phases) do
		phase.baseRadius = phase.baseRadius or phase.radius
		phase.radius = math.floor(phase.baseRadius * scale + 0.5)
	end
	config.arenaRadius = ARENA.radius

	logger.info("[BattleRoyale] Arena ready at ({}, {}, {}), radius {}, {} tiles ({} walkable)", ARENA.center.x, ARENA.center.y, ARENA.center.z, ARENA.radius, count, open)
	return true
end

local function walkable(position)
	local tile = Tile(position)
	return tile and tile:getGround() and not tile:hasFlag(TILESTATE_BLOCKSOLID) and tile:getCreatureCount() == 0
end

local function randomArenaPosition(margin)
	local c, r = ARENA.center, ARENA.radius - (margin or 1)
	-- The map area is not a full square, so many random points fall outside it
	for _ = 1, 300 do
		local position = Position(c.x + math.random(-r, r), c.y + math.random(-r, r), c.z)
		if isArenaPosition(position) and walkable(position) then
			return position
		end
	end
	return nil
end

-- Removes dropped items, corpses, fields and monsters left by the previous match. Items placed on the
-- map (walls, decoration) are kept: only what exceeds the startup snapshot of each tile is removed.
local function cleanArena()
	for key in pairs(BR.arenaTiles or {}) do
		local tile = Tile(math.floor(key / 65536), key % 65536, ARENA.center.z)
		if tile then
			for _, creature in ipairs(tile:getCreatures() or {}) do
				if creature:isMonster() then
					creature:remove()
				end
			end
			local keep = {}
			for id, amount in pairs(BR.arenaOriginal[key] or {}) do
				keep[id] = amount
			end
			for _, item in ipairs(tile:getItems() or {}) do
				local id = item:getId()
				if (keep[id] or 0) > 0 then
					keep[id] = keep[id] - 1
				else
					item:remove()
				end
			end
		end
	end
end

local function spawnLoot()
	local spawned = 0
	for _ = 1, ARENA.lootCount do
		local entry = Core.rollLoot(BR.resolved.loot)
		local position = randomArenaPosition(1)
		if entry and position then
			local item = Game.createItem(entry[1], entry[2], position)
			if item then
				spawned = spawned + 1
			end
		end
	end
	for _ = 1, ARENA.monsterCount do
		local position = randomArenaPosition(3)
		if position then
			Game.createMonster(ARENA.monsters[math.random(#ARENA.monsters)], position, false, true)
		end
	end
	return spawned
end

-- ---------------------------------------------------------------------------------------------------------
-- Character snapshot and restore
-- ---------------------------------------------------------------------------------------------------------
-- Equipment slots only: CONST_SLOT_LAST also covers the store inbox, which must never be stashed or cleared
local SKILLS = { SKILL_FIST, SKILL_CLUB, SKILL_SWORD, SKILL_AXE, SKILL_DISTANCE, SKILL_SHIELD }

local function snapshotKv(player)
	return player:kv():scoped(KV_SCOPE)
end

local function findHolder(player)
	local inbox = player:getInbox()
	if not inbox then
		return nil
	end
	for index = inbox:getSize() - 1, 0, -1 do
		local item = inbox:getItem(index)
		if item and item:getCustomAttribute(HOLDER_ATTR) then
			return item
		end
	end
	return nil
end

local function stashEquipment(player)
	local inbox = player:getInbox()
	if not inbox then
		return false
	end
	local holder = Game.createItem(HOLDER_ITEM, 1)
	if not holder then
		return false
	end
	holder:setCustomAttribute(HOLDER_ATTR, player:getGuid())
	if holder:moveTo(inbox) == false then
		holder:remove()
		return false
	end
	for slot = CONST_SLOT_FIRST, CONST_SLOT_AMMO do
		local item = player:getSlotItem(slot)
		if item then
			item:setCustomAttribute(SLOT_ATTR, slot)
			item:moveTo(holder)
		end
	end
	return true
end

local function clearEquipment(player)
	for slot = CONST_SLOT_FIRST, CONST_SLOT_AMMO do
		local item = player:getSlotItem(slot)
		if item then
			item:remove()
		end
	end
end

local function restoreEquipment(player)
	local holder = findHolder(player)
	if not holder then
		return
	end
	local items = {}
	for index = holder:getSize() - 1, 0, -1 do
		items[#items + 1] = holder:getItem(index)
	end
	for _, item in ipairs(items) do
		local slot = tonumber(item:getCustomAttribute(SLOT_ATTR))
		item:removeCustomAttribute(SLOT_ATTR)
		if slot and not player:getSlotItem(slot) then
			item:moveToSlot(player, slot)
		end
	end
	-- Anything that could not be equipped stays in the inbox, outside the holder
	local inbox = player:getInbox()
	for index = holder:getSize() - 1, 0, -1 do
		local item = holder:getItem(index)
		if item and inbox then
			item:moveTo(inbox)
		end
	end
	holder:remove()
end

local function takeSnapshot(player)
	local skills = {}
	for _, skill in ipairs(SKILLS) do
		skills["s" .. skill] = { level = player:getSkillLevel(skill), tries = player:getSkillTries(skill) }
	end
	local position = player:getPosition()
	snapshotKv(player):set("snapshot", {
		level = player:getLevel(),
		experience = player:getExperience(),
		magic = player:getBaseMagicLevel(),
		manaSpent = player:getManaSpent(),
		skills = skills,
		maxHealth = player:getMaxHealth(),
		maxMana = player:getMaxMana(),
		health = player:getHealth(),
		mana = player:getMana(),
		x = position.x,
		y = position.y,
		z = position.z,
	})
end

local function clearConditions(player)
	for _, condition in ipairs(CLEARED_CONDITIONS) do
		player:removeCondition(condition)
	end
end

function BR.restore(player)
	local kv = snapshotKv(player)
	local snapshot = kv:get("snapshot")
	if not snapshot then
		return false
	end

	clearConditions(player)
	clearEquipment(player)

	player:setLevel(math.floor(snapshot.level))
	local extra = math.floor(snapshot.experience) - player:getExperience()
	if extra > 0 then
		player:addExperience(extra, false)
	end
	player:setMagicLevel(math.floor(snapshot.magic), math.floor(snapshot.manaSpent))
	for key, values in pairs(snapshot.skills or {}) do
		local skill = tonumber(tostring(key):sub(2))
		if skill then
			player:setSkillLevel(skill, math.floor(values.level), math.floor(values.tries or 0))
		end
	end
	player:setMaxHealth(math.floor(snapshot.maxHealth))
	player:setMaxMana(math.floor(snapshot.maxMana))
	player:addHealth(math.floor(snapshot.health) - player:getHealth())
	player:addMana(math.floor(snapshot.mana) - player:getMana())

	restoreEquipment(player)
	player:setSkull(SKULL_NONE)
	player:setSkullTime(0)
	player:unregisterEvent("BattleRoyaleHealth")
	player:setSkillLoss(true)
	player:teleportTo(Position(math.floor(snapshot.x), math.floor(snapshot.y), math.floor(snapshot.z)))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	kv:remove("snapshot")
	player:save()
	return true
end

local function equalize(player)
	local vocation = player:getVocation()
	local baseId = vocation:getBaseId()
	local stats = Core.combatStats(baseId)
	local maxHealth, maxMana = Core.statsForLevel(config.matchLevel, vocation:getHealthGain(), vocation:getManaGain())

	player:setLevel(config.matchLevel)
	player:setMagicLevel(stats.magic)
	for skill, level in pairs(stats.skills) do
		player:setSkillLevel(skill, level)
	end
	player:setMaxHealth(maxHealth)
	player:setMaxMana(maxMana)
	player:addHealth(maxHealth)
	player:addMana(maxMana)

	local backpack = player:addItem(HOLDER_ITEM, 1, false, 1, CONST_SLOT_BACKPACK)
	for _, entry in ipairs(BR.resolved.kits[baseId] or {}) do
		local id, count, slot = entry[1], entry[2], entry[3]
		if slot then
			player:addItem(id, count, false, 1, slot)
		elseif backpack then
			backpack:addItem(id, count)
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Match flow
-- ---------------------------------------------------------------------------------------------------------
local function aliveCount()
	local count = 0
	for _, entry in pairs(BR.match.players) do
		if entry.alive then
			count = count + 1
		end
	end
	return count
end

-- A solo practice match (/brsolo) only ends when its single player is eliminated.
local function lastStanding()
	return BR.match and BR.match.solo and 0 or 1
end

local finishMatch

function BR.eliminate(player, killer)
	local match = BR.match
	if not match then
		return
	end
	local entry = match.players[player:getGuid()]
	if not entry or not entry.alive then
		return
	end
	entry.alive = false
	entry.placement = aliveCount() + 1
	entry.survived = os.time() - match.startedAt

	local killerName = nil
	if killer and killer:isPlayer() and killer:getGuid() ~= player:getGuid() then
		local killerEntry = match.players[killer:getGuid()]
		if killerEntry then
			killerEntry.kills = killerEntry.kills + 1
		end
		killerName = killer:getName()
	end

	player:getPosition():sendMagicEffect(CONST_ME_MORTAREA)
	BR.restore(player)
	say(player, string.format("Quedaste en el puesto %d de %d.", entry.placement, match.size))
	broadcastMatch(killerName and string.format("%s fue eliminado por %s. Quedan %d.", player:getName(), killerName, aliveCount())
		or string.format("%s fue eliminado. Quedan %d.", player:getName(), aliveCount()), MESSAGE_STATUS)

	if aliveCount() <= lastStanding() then
		finishMatch()
	end
end

finishMatch = function()
	local match = BR.match
	if not match or BR.state == "ending" then
		return
	end
	BR.state = "ending"
	stopEvent(match.tickEvent)

	local winnerGuid = 0
	for guid, entry in pairs(match.players) do
		if entry.alive then
			entry.alive = false
			entry.placement = 1
			entry.survived = os.time() - match.startedAt
			winnerGuid = guid
			local player = Player(guid)
			if player then
				BR.restore(player)
				if not match.solo then
					say(player, string.format("\161Ganaste el Battle Royale con %d kills!", entry.kills))
				end
			end
		end
	end

	if match.solo then
		-- Practice match: no ratings and no match history
		logger.info("[BattleRoyale] Solo practice match ended")
		BR.match = nil
		cleanArena()
		BR.state = "idle"
		if queueSize() >= config.minPlayers then
			BR.startCountdown()
		end
		return
	end

	local season = currentSeason()
	local ranked = match.size >= config.minRankedPlayers
	local participants = {}
	for guid, entry in pairs(match.players) do
		participants[#participants + 1] = { id = guid, rating = entry.rating, placement = entry.placement or match.size, kills = entry.kills, survived = entry.survived or 0 }
	end
	local changes = ranked and Core.ratingChanges(participants) or {}
	for _, p in ipairs(participants) do
		local row = BR.getRating(p.id, season)
		local delta = changes[p.id] or 0
		row.rating = math.max(config.ratingFloor, row.rating + delta)
		row.best = math.max(row.best, row.rating)
		row.matches = row.matches + 1
		row.kills = row.kills + p.kills
		row.score = row.score + Core.matchScore(p.placement, match.size, p.kills, p.survived)
		if p.placement == 1 then
			row.wins = row.wins + 1
		end
		saveRating(p.id, season, row)
		local player = Player(p.id)
		if player then
			if ranked then
				say(player, string.format("Rating: %d (%+d). Liga: %s.", row.rating, delta, Core.leagueFor(row.rating).name), MESSAGE_STATUS)
			else
				say(player, string.format("Partida no clasificatoria (menos de %d jugadores).", config.minRankedPlayers), MESSAGE_STATUS)
			end
		end
	end
	db.query(string.format("INSERT INTO `battle_royale_matches` (`season`, `started_at`, `ended_at`, `players`, `ranked`, `winner_id`) VALUES (%d, %d, %d, %d, %d, %d)", season, match.startedAt, os.time(), match.size, ranked and 1 or 0, winnerGuid))
	logger.info("[BattleRoyale] Match ended: {} players, winner {}, ranked {}", match.size, winnerGuid, tostring(ranked))

	BR.match = nil
	cleanArena()
	BR.state = "idle"
	if queueSize() >= config.minPlayers then
		BR.startCountdown()
	end
end

local function zoneTick()
	local match = BR.match
	if not match or BR.state ~= "running" then
		return
	end
	local now = os.time()
	local elapsed = now - match.startedAt
	local inGrace = elapsed < config.graceTime
	local zoneElapsed = math.max(0, elapsed - config.graceTime)
	local radius, phase, damage, shrinking = Core.zoneAt(zoneElapsed)

	if radius ~= match.lastRadius then
		if match.lastRadius and radius < match.lastRadius and not match.announcedShrink[phase] then
			match.announcedShrink[phase] = true
			broadcastMatch(string.format("\161La zona se est\225 cerrando! Fase %d.", phase))
		end
		match.lastRadius = radius
	end

	-- Border effect every 2 seconds
	if elapsed % 2 == 0 then
		local c = ARENA.center
		for d = -radius, radius do
			for _, pos in ipairs({ Position(c.x + d, c.y - radius, c.z), Position(c.x + d, c.y + radius, c.z), Position(c.x - radius, c.y + d, c.z), Position(c.x + radius, c.y + d, c.z) }) do
				pos:sendMagicEffect(CONST_ME_PURPLEENERGY)
			end
		end
	end

	for guid, entry in pairs(match.players) do
		if entry.alive then
			local player = Player(guid)
			if not player then
				-- Logged out somehow: eliminated, restored on next login
				entry.alive = false
				entry.placement = aliveCount() + 1
				entry.survived = elapsed
			elseif not inGrace then
				if Core.isOutsideZone(player:getPosition(), ARENA.center, radius) or not isArenaPosition(player:getPosition()) then
					local amount = math.max(1, math.floor(player:getMaxHealth() * damage))
					player:getPosition():sendMagicEffect(CONST_ME_MAGIC_RED)
					if amount >= player:getHealth() then
						BR.eliminate(player, nil)
					else
						player:addHealth(-amount)
					end
				end
				if BR.match and entry.alive then
					local idle = now - entry.lastCombat
					if idle >= config.idleLimit then
						say(player, "Eliminado por inactividad.")
						BR.eliminate(player, nil)
					elseif idle >= config.idleWarning and not entry.idleWarned then
						entry.idleWarned = true
						say(player, string.format("Pelea o ser\225s eliminado por inactividad en %d segundos.", config.idleLimit - idle))
					end
				end
			end
		end
	end

	if BR.match and aliveCount() <= lastStanding() then
		finishMatch()
		return
	end
	if BR.match then
		match.tickEvent = addEvent(zoneTick, 1000)
	end
end

-- soloPlayer starts a practice match (/brsolo) for that player only, bypassing the queue and the minimum.
local function startMatch(soloPlayer)
	if not soloPlayer and BR.state ~= "countdown" then
		return
	end
	local entrants = {}
	if soloPlayer then
		entrants[1] = soloPlayer
	else
		for guid in pairs(BR.queue) do
			local player = Player(guid)
			if player and not player:isPzLocked() and not snapshotKv(player):get("snapshot") then
				entrants[#entrants + 1] = player
			end
		end
		BR.queue = {}
	end
	local minimum = soloPlayer and 1 or config.minPlayers
	if #entrants < minimum then
		BR.state = "idle"
		for _, player in ipairs(entrants) do
			BR.queue[player:getGuid()] = player:getIp()
			say(player, "No hay suficientes jugadores disponibles; sigues en la cola.")
		end
		return
	end

	cleanArena()
	local spawned = spawnLoot()
	local season = currentSeason()
	BR.match = { players = {}, size = #entrants, startedAt = os.time(), announcedShrink = {}, season = season, solo = soloPlayer ~= nil }
	BR.state = "running"

	for _, player in ipairs(entrants) do
		local spawn = randomArenaPosition(4)
		if spawn and stashEquipment(player) then
			takeSnapshot(player)
			player:save()
			equalize(player)
			player:registerEvent("BattleRoyaleHealth")
			-- A death in the arena must never cost the real character level or skills
			player:setSkillLoss(false)
			player:teleportTo(spawn)
			spawn:sendMagicEffect(CONST_ME_TELEPORT)
			BR.match.players[player:getGuid()] = { alive = true, kills = 0, rating = BR.getRating(player:getGuid(), season).rating, lastCombat = os.time() }
			say(player, string.format("\161Comienza la partida! %d jugadores. Tienes %d segundos de gracia: busca equipo en el suelo.", #entrants, config.graceTime))
		else
			logger.warn("[BattleRoyale] Could not prepare {}: {}", player:getName(), spawn and "equipment could not be stored in the inbox" or "no free arena tile")
			say(player, "No se pudo preparar tu personaje; intenta de nuevo.")
		end
	end
	local count = 0
	for _ in pairs(BR.match.players) do
		count = count + 1
	end
	BR.match.size = count
	logger.info("[BattleRoyale] Match started with {} players, {} loot items", count, spawned)
	if count < minimum then
		finishMatch()
		return
	end
	BR.match.tickEvent = addEvent(zoneTick, 1000)
end

local function countdownTick(remaining)
	if BR.state ~= "countdown" then
		return
	end
	if queueSize() < config.minPlayers then
		BR.state = "idle"
		broadcastQueue("La cuenta regresiva se cancel\243: faltan jugadores.")
		return
	end
	if remaining <= 0 then
		startMatch()
		return
	end
	if remaining == config.lobbyCountdown or remaining == 30 or remaining == 10 or remaining <= 3 then
		broadcastQueue(string.format("La partida empieza en %d segundos (%d en cola).", remaining, queueSize()))
	end
	BR.countdownEvent = addEvent(countdownTick, 1000, remaining - 1)
end

function BR.startCountdown()
	if BR.state ~= "idle" then
		return
	end
	BR.state = "countdown"
	countdownTick(config.lobbyCountdown)
end

function BR.join(player)
	if BR.state == "disabled" then
		say(player, "El modo est\225 desactivado.")
		return
	end
	local guid = player:getGuid()
	if BR.queue[guid] then
		say(player, "Ya est\225s en la cola. Usa !br salir para salir.")
		return
	end
	if BR.match and BR.match.players[guid] and BR.match.players[guid].alive then
		say(player, "Ya est\225s en una partida.")
		return
	end
	if player:getLevel() < config.minLevel then
		say(player, string.format("Necesitas nivel %d para jugar.", config.minLevel))
		return
	end
	if player:isPzLocked() or player:getCondition(CONDITION_INFIGHT) then
		say(player, "No puedes entrar en combate.")
		return
	end
	if queueSize() >= config.maxPlayers then
		say(player, "La cola est\225 llena.")
		return
	end
	if not ALLOW_SAME_IP and not Core.ipAllowed(BR.queue, player:getIp()) then
		say(player, "Ya hay un personaje de tu conexi\243n en la cola.")
		return
	end
	BR.queue[guid] = player:getIp()
	say(player, string.format("Entraste en la cola (%d/%d). M\237nimo para empezar: %d.", queueSize(), config.maxPlayers, config.minPlayers))
	if BR.state == "idle" and queueSize() >= config.minPlayers then
		BR.startCountdown()
	end
end

function BR.leave(player)
	if BR.queue[player:getGuid()] then
		BR.queue[player:getGuid()] = nil
		say(player, "Saliste de la cola.")
	else
		say(player, "No est\225s en la cola.")
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------
local health = CreatureEvent("BattleRoyaleHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local match = BR.match
	local player = creature and creature:getPlayer()
	local entry = match and player and match.players[player:getGuid()]
	if not entry or not entry.alive then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end

	local now = os.time()
	if now - match.startedAt < config.graceTime then
		return 0, primaryType, 0, secondaryType
	end
	entry.lastCombat = now
	entry.idleWarned = false
	if attacker and attacker:isPlayer() then
		local attackerEntry = match.players[attacker:getGuid()]
		if attackerEntry then
			attackerEntry.lastCombat = now
			attackerEntry.idleWarned = false
		end
	end

	local total = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if total >= player:getHealth() then
		addEvent(function(guid, attackerId)
			local target = Player(guid)
			if target then
				BR.eliminate(target, attackerId and Creature(attackerId) or nil)
			end
		end, 0, player:getGuid(), attacker and attacker:getId() or nil)
		return 0, primaryType, 0, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
health:register()

local login = CreatureEvent("BattleRoyaleLogin")
function login.onLogin(player)
	-- A snapshot with no live match entry means the match ended (or the server stopped) while away
	local entry = BR.match and BR.match.players[player:getGuid()]
	if snapshotKv(player):get("snapshot") and not (entry and entry.alive) then
		BR.restore(player)
		say(player, "Tu personaje fue restaurado tras la partida.")
	elseif entry and entry.alive then
		player:registerEvent("BattleRoyaleHealth")
		player:setSkillLoss(false)
	end
	if BR.tableReady then
		claimRewards(player)
	end
	return true
end
login:register()

local logout = CreatureEvent("BattleRoyaleLogout")
function logout.onLogout(player)
	BR.queue[player:getGuid()] = nil
	return true
end
logout:register()

local startup = GlobalEvent("BattleRoyaleStartup")
function startup.onStartup()
	if not ensureTables() then
		logger.error("[BattleRoyale] Could not create the database tables, mode disabled")
		BR.state = "disabled"
		return true
	end
	rolloverSeason()
	BR.resolved = resolveItems()
	BR.arenaReady = buildArena()
	if not BR.arenaReady then
		BR.state = "disabled"
	end
	return true
end
startup:register()

-- Monthly rollover while the server stays online
local seasonCheck = GlobalEvent("BattleRoyaleSeason")
function seasonCheck.onThink(interval)
	if BR.tableReady then
		rolloverSeason()
	end
	return true
end
seasonCheck:interval(60 * 60 * 1000)
seasonCheck:register()

-- ---------------------------------------------------------------------------------------------------------
-- !br command
-- ---------------------------------------------------------------------------------------------------------
local command = TalkAction("!br")
function command.onSay(player, words, param)
	param = (param or ""):lower():trim()
	if param == "" or param == "entrar" or param == "join" then
		BR.join(player)
	elseif param == "salir" or param == "leave" then
		BR.leave(player)
	elseif param == "rank" or param == "rating" then
		local row = BR.getRating(player:getGuid())
		local league = Core.leagueFor(row.rating)
		local title = snapshotKv(player):get("title")
		say(player, string.format("Temporada %d - Rating %d (%s), mejor %d. Partidas %d, victorias %d, kills %d, puntos %d.%s", currentSeason(), row.rating, league.name, row.best, row.matches, row.wins, row.kills, row.score, title and (" T\237tulo: " .. title) or ""), MESSAGE_LOOK)
	elseif param == "top" then
		local result = db.storeQuery(string.format("SELECT p.`name`, r.`rating`, r.`wins` FROM `battle_royale_ratings` r JOIN `players` p ON p.`id` = r.`player_id` WHERE r.`season` = %d ORDER BY r.`rating` DESC, r.`wins` DESC LIMIT 10", currentSeason()))
		local lines = { "Top 10 de la temporada:" }
		if result then
			local position = 0
			repeat
				position = position + 1
				lines[#lines + 1] = string.format("%d. %s - %d (%d victorias)", position, Result.getString(result, "name"), Result.getNumber(result, "rating"), Result.getNumber(result, "wins"))
			until not Result.next(result)
			Result.free(result)
		else
			lines[#lines + 1] = "Todav\237a no hay partidas."
		end
		player:showTextDialog(HOLDER_ITEM, table.concat(lines, "\n"))
	else
		local stateText = { idle = "esperando jugadores", countdown = "cuenta regresiva", running = "partida en curso", ending = "terminando", disabled = "desactivado" }
		say(player, string.format("Estado: %s. En cola: %d. Comandos: !br, !br salir, !br rank, !br top.", stateText[BR.state] or BR.state, queueSize()), MESSAGE_LOOK)
	end
	return true
end
command:separator(" ")
command:groupType("normal")
command:register()

-- /brsolo (GOD only): practice match alone in the arena (monsters, loot and shrinking zone, no ratings).
-- "/brsolo stop" ends it. Lets one person test the whole match flow without a second player.
local solo = TalkAction("/brsolo")
function solo.onSay(player, words, param)
	param = (param or ""):lower():trim()
	if param == "stop" then
		if BR.match and BR.match.solo and BR.match.players[player:getGuid()] then
			BR.eliminate(player, nil)
		else
			say(player, "No est\225s en una pr\225ctica en solitario.")
		end
		return true
	end
	if BR.state ~= "idle" then
		say(player, "Hay una cola o una partida activa; espera a que termine.")
		return true
	end
	if BR.queue[player:getGuid()] or snapshotKv(player):get("snapshot") then
		say(player, "Sal de la cola (!br salir) o termina tu partida antes de practicar.")
		return true
	end
	if player:isPzLocked() or player:getCondition(CONDITION_INFIGHT) then
		say(player, "No puedes entrar en combate.")
		return true
	end
	startMatch(player)
	return true
end
solo:separator(" ")
solo:groupType("god")
solo:register()

-- /brtest (GOD only): snapshot -> equalize -> restore on the caller and compare every saved value.
-- Verifies the riskiest part of the mode without needing a full match.
local selfTest = TalkAction("/brtest")
function selfTest.onSay(player, words, param)
	if BR.match and BR.match.players[player:getGuid()] then
		say(player, "No puedes probar dentro de una partida.")
		return true
	end
	if not BR.resolved then
		say(player, "El modo no est\225 inicializado.")
		return true
	end
	local function capture()
		local values = { level = player:getLevel(), experience = player:getExperience(), magic = player:getBaseMagicLevel(), manaSpent = player:getManaSpent(), maxHealth = player:getMaxHealth(), maxMana = player:getMaxMana() }
		for _, skill in ipairs(SKILLS) do
			values["skill" .. skill] = player:getSkillLevel(skill) .. "/" .. player:getSkillTries(skill)
		end
		for slot = CONST_SLOT_FIRST, CONST_SLOT_AMMO do
			local item = player:getSlotItem(slot)
			values["slot" .. slot] = item and item:getId() or 0
		end
		local position = player:getPosition()
		values.position = position.x .. "," .. position.y .. "," .. position.z
		return values
	end

	local before = capture()
	if not stashEquipment(player) then
		say(player, "FALL\211: no se pudo guardar el equipo.")
		return true
	end
	takeSnapshot(player)
	equalize(player)
	say(player, string.format("Igualado a nivel %d con el kit. Restaurando en 3 segundos...", player:getLevel()))
	local guid = player:getGuid()
	addEvent(function()
		local target = Player(guid)
		if not target then
			return
		end
		BR.restore(target)
		local after = capture()
		local diffs = {}
		for key, value in pairs(before) do
			if after[key] ~= value then
				diffs[#diffs + 1] = string.format("%s: %s -> %s", key, tostring(value), tostring(after[key]))
			end
		end
		if #diffs == 0 then
			say(target, "PRUEBA OK: personaje restaurado exactamente.")
			logger.info("[BattleRoyale] /brtest passed for {}", target:getName())
		else
			say(target, "PRUEBA FALL\211: " .. table.concat(diffs, "; "))
			logger.error("[BattleRoyale] /brtest failed for {}: {}", target:getName(), table.concat(diffs, "; "))
		end
	end, 3000)
	return true
end
selfTest:separator(" ")
selfTest:groupType("god")
selfTest:register()
