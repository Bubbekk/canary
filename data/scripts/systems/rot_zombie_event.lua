-- RoT Zombie Event: todos los dias a las 21:00 se abre la arena (la misma del Battle Royale).
-- Los jugadores entran con !zombie durante 3 minutos. Al empezar aparecen zombies sin parar,
-- cada vez mas rapido. No se pueden atacar: un solo toque te elimina. Gana el ultimo en pie.
--
-- - Sin PvP entre participantes y sin danio real: nadie puede morir.
-- - Al ser eliminado vuelves exactamente a donde estabas antes de entrar.
-- - Premios en oro al banco (y Tibia Coins para el ganador). Todo configurable abajo.
-- - Convive con el Battle Royale: si hay partida de BR se pospone, y el BR espera si hay Zombie Event.
-- Textos en Latin-1 (\225 = a con tilde, \161 = signo de exclamacion inicial) porque el cliente usa cp1252.
-- GOD: /zombie open | start | stop

ZombieEvent = ZombieEvent or {}
local ZE = ZombieEvent

local config = {
	openTime = "21:00:00",
	joinSeconds = 3 * 60,
	minPlayers = 2,
	maxDuration = 20 * 60, -- por si quedan jugadores imposibles de alcanzar
	monsterName = "Event Zombie",
	spawnInterval = 5, -- segundos entre oleadas
	spawnBase = 2, -- zombies por oleada al inicio
	spawnGrowthEvery = 20, -- cada N segundos la oleada trae un zombie mas
	maxZombies = 150,
	zoneRadius = 25, -- casillas desde el centro de la arena; fuera de ahi quedas eliminado
	minLevel = 8,
	rewards = {
		-- por puesto final: oro al banco; coins solo para el primero
		[1] = { gold = 50000, coins = 5 },
		[2] = { gold = 25000 },
		[3] = { gold = 10000 },
	},
	survivorGold = 2000, -- para quien aguante al menos survivorSeconds sin quedar en el podio
	survivorSeconds = 120,
}

ZE.state = "idle" -- idle | open | running
ZE.players = {} -- [guid] = { back = Position, joinedAt = time, alive = true }
ZE.events = {}
ZE.startedAt = 0
ZE.eliminated = 0 -- orden de eliminacion para calcular el puesto
ZE.joined = 0

local function say(player, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
end

local function broadcast(text)
	Game.broadcastMessage(text, MESSAGE_GAME_HIGHLIGHT)
end

local function arenaReady()
	return BattleRoyale and BattleRoyale.arenaTiles and BattleRoyale.arenaZ and BattleRoyale.arenaCenter
end

local function inZone(position)
	local center = BattleRoyale.arenaCenter
	return position.z == center.z and math.abs(position.x - center.x) <= config.zoneRadius and math.abs(position.y - center.y) <= config.zoneRadius
end

-- Solo las casillas de la arena dentro del radio del evento
local function forEachArenaTile(fn)
	local center = BattleRoyale.arenaCenter
	for x = center.x - config.zoneRadius, center.x + config.zoneRadius do
		for y = center.y - config.zoneRadius, center.y + config.zoneRadius do
			if BattleRoyale.arenaTiles[x * 65536 + y] then
				local tile = Tile(x, y, BattleRoyale.arenaZ)
				if tile then
					fn(tile)
				end
			end
		end
	end
end

local function walkableTiles()
	local list = {}
	forEachArenaTile(function(tile)
		if not tile:hasFlag(TILESTATE_BLOCKSOLID) and tile:getGround() then
			list[#list + 1] = tile:getPosition()
		end
	end)
	return list
end

local function randomFreeTile(tiles, avoidPlayers)
	for _ = 1, 30 do
		local position = tiles[math.random(#tiles)]
		local tile = Tile(position)
		if tile and not tile:getTopCreature() then
			if not avoidPlayers then
				return position
			end
			local nearPlayer = false
			for _, spectator in ipairs(Game.getSpectators(position, false, true, 3, 3, 3, 3)) do
				nearPlayer = nearPlayer or spectator:isPlayer()
			end
			if not nearPlayer then
				return position
			end
		end
	end
	return nil
end

local function cancelEvents()
	for _, id in ipairs(ZE.events) do
		stopEvent(id)
	end
	ZE.events = {}
end

local function schedule(fn, ms)
	ZE.events[#ZE.events + 1] = addEvent(fn, ms)
end

local function aliveList()
	local list = {}
	for guid, entry in pairs(ZE.players) do
		if entry.alive then
			list[#list + 1] = guid
		end
	end
	return list
end

local function zombieCount()
	local count = 0
	forEachArenaTile(function(tile)
		for _, creature in ipairs(tile:getCreatures() or {}) do
			if creature:isMonster() and creature:getName() == config.monsterName then
				count = count + 1
			end
		end
	end)
	return count
end

-- Vacia los cofres del Battle Royale para que nadie se lleve su loot
local function emptyChests()
	for _, chest in ipairs(BattleRoyale.arenaChests or {}) do
		local tile = Tile(chest.x, chest.y, BattleRoyale.arenaZ)
		local container = tile and tile:getItemById(chest.id)
		if container and container:isContainer() then
			for _, item in ipairs(container:getItems() or {}) do
				item:remove()
			end
		end
	end
end

local function sendBack(player, entry)
	player:unregisterEvent("ZombieEventHealth")
	local back = entry and entry.back or player:getTown():getTemplePosition()
	player:teleportTo(back)
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
end

local function giveReward(player, place, survivedSeconds)
	local reward = config.rewards[place]
	local text
	if reward then
		player:setBankBalance(player:getBankBalance() + reward.gold)
		text = string.format("%d de oro", reward.gold)
		if reward.coins then
			player:addTibiaCoins(reward.coins)
			text = text .. string.format(" y %d Tibia Coins", reward.coins)
		end
	elseif survivedSeconds >= config.survivorSeconds then
		player:setBankBalance(player:getBankBalance() + config.survivorGold)
		text = string.format("%d de oro por aguantar %d minutos", config.survivorGold, math.floor(survivedSeconds / 60))
	end
	if text then
		say(player, string.format("[Zombie Event] Puesto %d. Recibes %s (en tu banco).", place, text))
	end
end

local function finish(reason)
	if ZE.state == "idle" then
		return
	end
	cancelEvents()
	local alive = aliveList()
	local now = os.time()
	-- Los que siguen vivos comparten el mejor puesto disponible
	local place = ZE.joined - #alive + 1
	if ZE.state == "running" then
		if #alive == 1 then
			local winner = Player(alive[1])
			if winner then
				broadcast(string.format("[Zombie Event] \161%s sobrevivi\243 a los zombies y gana el Zombie Event!", winner:getName()))
			end
		elseif #alive > 1 then
			broadcast(string.format("[Zombie Event] El evento termin\243 con %d supervivientes. \161Felicidades!", #alive))
		end
	end
	for _, guid in ipairs(alive) do
		local player = Player(guid)
		local entry = ZE.players[guid]
		if player then
			if ZE.state == "running" then
				giveReward(player, place, now - ZE.startedAt)
			elseif reason then
				say(player, "[Zombie Event] " .. reason)
			end
			sendBack(player, entry)
		end
	end
	if arenaReady() then
		BattleRoyale.cleanArena()
	end
	ZE.state = "idle"
	ZE.players = {}
	ZE.joined = 0
	ZE.eliminated = 0
	logger.info("[ZombieEvent] finished ({})", reason or "normal")
end

function ZE.eliminate(player, silent)
	local guid = player:getGuid()
	local entry = ZE.players[guid]
	if not entry or not entry.alive then
		return
	end
	entry.alive = false
	ZE.eliminated = ZE.eliminated + 1
	local place = ZE.joined - ZE.eliminated + 1
	local survived = os.time() - ZE.startedAt
	if ZE.state == "running" then
		if not silent then
			broadcast(string.format("[Zombie Event] %s fue alcanzado por los zombies. Quedan %d jugadores.", player:getName(), #aliveList()))
		end
		giveReward(player, place, survived)
	end
	sendBack(player, entry)
	if ZE.state == "running" and #aliveList() <= 1 then
		schedule(function()
			finish()
		end, 1500)
	end
end

local function spawnWave()
	if ZE.state ~= "running" then
		return
	end
	local elapsed = os.time() - ZE.startedAt
	-- Quien salga de la zona del evento queda eliminado
	for _, guid in ipairs(aliveList()) do
		local player = Player(guid)
		if player and not inZone(player:getPosition()) then
			say(player, "[Zombie Event] Saliste de la zona del evento.")
			ZE.eliminate(player)
		end
	end
	if ZE.state ~= "running" then
		return
	end
	local amount = config.spawnBase + math.floor(elapsed / config.spawnGrowthEvery)
	local current = zombieCount()
	local tiles = walkableTiles()
	for _ = 1, amount do
		if current >= config.maxZombies then
			break
		end
		local position = randomFreeTile(tiles, true) or randomFreeTile(tiles, false)
		if position and Game.createMonster(config.monsterName, position, false, true) then
			position:sendMagicEffect(CONST_ME_MORTAREA)
			current = current + 1
		end
	end
	if elapsed > 0 and elapsed % 60 == 0 then
		for _, guid in ipairs(aliveList()) do
			local player = Player(guid)
			if player then
				say(player, string.format("[Zombie Event] %d minutos. %d zombies en la arena, %d jugadores vivos.", math.floor(elapsed / 60), current, #aliveList()))
			end
		end
	end
	if elapsed >= config.maxDuration then
		finish("Se alcanz\243 el tiempo m\225ximo.")
		return
	end
	schedule(spawnWave, config.spawnInterval * 1000)
end

function ZE.start()
	if ZE.state ~= "open" then
		return
	end
	cancelEvents()
	local alive = aliveList()
	if #alive < config.minPlayers then
		-- Sigue en "open", asi que finish() devuelve a los jugadores sin repartir premios
		broadcast(string.format("[Zombie Event] No hubo suficientes jugadores (m\237nimo %d). El evento se cancela.", config.minPlayers))
		finish("No hubo suficientes jugadores. Vuelves a tu posici\243n.")
		return
	end
	ZE.state = "running"
	ZE.startedAt = os.time()
	ZE.joined = #alive
	ZE.eliminated = 0
	broadcast(string.format("[Zombie Event] \161Empieza el Zombie Event con %d jugadores! Los zombies no se pueden matar: si te tocan, quedas fuera. \161Corre!", #alive))
	for _, guid in ipairs(alive) do
		local player = Player(guid)
		if player then
			say(player, "[Zombie Event] \161Huye de los zombies! Un solo toque te elimina. El \250ltimo en pie gana.")
		end
	end
	schedule(spawnWave, 3000)
end

function ZE.open(manual)
	if ZE.state ~= "idle" then
		return false
	end
	if not arenaReady() then
		logger.error("[ZombieEvent] arena not ready (Battle Royale arena missing)")
		return false
	end
	if BattleRoyale.state ~= "idle" then
		if not manual then
			broadcast("[Zombie Event] Hay una partida de Battle Royale en la arena. El Zombie Event empezar\225 en 10 minutos.")
			schedule(function()
				ZE.open(false)
			end, 10 * 60 * 1000)
		end
		return false
	end
	ZE.state = "open"
	ZE.players = {}
	BattleRoyale.cleanArena()
	emptyChests()
	broadcast(string.format("[Zombie Event] \161El Zombie Event abre sus puertas! Escribe !zombie para entrar. Tienes %d minutos. Premio: %d de oro y %d Tibia Coins para el ganador.", math.floor(config.joinSeconds / 60), config.rewards[1].gold, config.rewards[1].coins))
	schedule(function()
		if ZE.state == "open" then
			broadcast("[Zombie Event] \161Queda 1 minuto para entrar con !zombie!")
		end
	end, (config.joinSeconds - 60) * 1000)
	schedule(ZE.start, config.joinSeconds * 1000)
	return true
end

function ZE.join(player)
	if ZE.state ~= "open" then
		if ZE.state == "running" then
			say(player, "[Zombie Event] El evento ya empez\243. Espera al pr\243ximo.")
		else
			say(player, string.format("[Zombie Event] No hay evento abierto. Todos los d\237as a las %s.", config.openTime:sub(1, 5)))
		end
		return
	end
	local guid = player:getGuid()
	if ZE.players[guid] then
		say(player, "[Zombie Event] Ya est\225s dentro.")
		return
	end
	if player:getLevel() < config.minLevel then
		say(player, string.format("[Zombie Event] Necesitas nivel %d.", config.minLevel))
		return
	end
	if player:isPzLocked() or player:getCondition(CONDITION_INFIGHT) then
		say(player, "[Zombie Event] No puedes entrar en combate. Espera a que se te pase.")
		return
	end
	local position = randomFreeTile(walkableTiles(), false)
	if not position then
		say(player, "[Zombie Event] La arena est\225 llena.")
		return
	end
	ZE.players[guid] = { back = player:getPosition(), joinedAt = os.time(), alive = true }
	player:registerEvent("ZombieEventHealth")
	player:teleportTo(position)
	position:sendMagicEffect(CONST_ME_TELEPORT)
	say(player, string.format("[Zombie Event] Est\225s dentro. Cuando empiece, huye de los zombies: un toque te elimina. No te alejes m\225s de %d casillas del centro ni ataques a nadie.", config.zoneRadius))
end

function ZE.leave(player)
	local entry = ZE.players[player:getGuid()]
	if not entry or not entry.alive then
		say(player, "[Zombie Event] No est\225s en el evento.")
		return
	end
	if ZE.state == "open" then
		entry.alive = false
		ZE.players[player:getGuid()] = nil
		sendBack(player, entry)
		say(player, "[Zombie Event] Saliste del evento.")
	else
		ZE.eliminate(player)
	end
end

-- Dentro del evento nadie recibe danio real: un zombie elimina, un jugador no hace nada.
local health = CreatureEvent("ZombieEventHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local player = creature and creature:getPlayer()
	local entry = player and ZE.players[player:getGuid()]
	if not entry or not entry.alive or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if attacker and attacker:isMonster() and attacker:getName() == config.monsterName and ZE.state == "running" then
		ZE.eliminate(player)
	end
	return 0, primaryType, 0, secondaryType
end
health:register()

local logout = CreatureEvent("ZombieEventLogout")
function logout.onLogout(player)
	local entry = ZE.players[player:getGuid()]
	if entry and entry.alive then
		entry.alive = false
		ZE.eliminated = ZE.eliminated + 1
		player:teleportTo(entry.back)
		if ZE.state == "running" and #aliveList() <= 1 then
			schedule(function()
				finish()
			end, 1500)
		end
	end
	return true
end
logout:register()

local login = CreatureEvent("ZombieEventLogin")
function login.onLogin(player)
	player:registerEvent("ZombieEventLogout")
	-- Si alguien quedo dentro de la arena por un reinicio, lo sacamos al templo
	if arenaReady() and ZE.state == "idle" then
		local pos = player:getPosition()
		if pos.z == BattleRoyale.arenaZ and BattleRoyale.arenaTiles[pos.x * 65536 + pos.y] and player:getGroup():getId() == 1 then
			player:teleportTo(player:getTown():getTemplePosition())
		end
	end
	return true
end
login:register()

local opener = GlobalEvent("ZombieEventOpen")
function opener.onTime(interval)
	ZE.open(false)
	return true
end
opener:time(config.openTime)
opener:register()

local talk = TalkAction("!zombie")
function talk.onSay(player, words, param)
	local action = param:trim():lower()
	if action == "salir" or action == "leave" then
		ZE.leave(player)
	else
		ZE.join(player)
	end
	return true
end
talk:separator(" ")
talk:groupType("normal")
talk:register()

local god = TalkAction("/zombie")
function god.onSay(player, words, param)
	local action = param:trim():lower()
	if action == "open" then
		if not ZE.open(true) then
			say(player, "No se pudo abrir (ya hay evento, hay BR en curso o la arena no est\225 lista).")
		end
	elseif action == "start" then
		if ZE.state == "open" then
			ZE.start()
		else
			say(player, "El evento no est\225 en fase de inscripci\243n.")
		end
	elseif action == "stop" then
		finish("El evento fue detenido por un administrador.")
		say(player, "Zombie Event detenido.")
	else
		say(player, string.format("Zombie Event: estado %s, %d jugadores. Uso: /zombie open | start | stop", ZE.state, #aliveList()))
	end
	return true
end
god:separator(" ")
god:groupType("god")
god:register()
