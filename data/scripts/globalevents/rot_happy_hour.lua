-- RoT Hora Feliz sorpresa: dos veces al dia, a una hora aleatoria, el servidor activa
-- 1 hora de experiencia doble o loot doble para todos. Se avisa 10 minutos antes.
--
-- Horarios (hora del servidor): una entre 11:00 y 16:00 y otra entre 18:00 y 23:00.
-- El tipo (exp/loot) se sortea cada dia de modo que haya una de cada.
-- El plan del dia y la hora feliz activa se guardan en KV para sobrevivir reinicios.
-- Textos en Latin-1 (\225 = a con tilde, \161 = signo de exclamacion inicial) porque el cliente usa cp1252.
-- GOD: /horafeliz exp|loot [minutos]   /horafeliz stop   /horafeliz info

RoTHappyHour = RoTHappyHour or {}
local HH = RoTHappyHour

local config = {
	duration = 60 * 60, -- segundos
	warning = 10 * 60, -- aviso previo
	slots = {
		{ fromHour = 11, toHour = 16 },
		{ fromHour = 18, toHour = 23 },
	},
	kinds = { "exp", "loot" },
}

local LABEL = { exp = "EXPERIENCIA DOBLE", loot = "LOOT DOBLE" }

local store = kv.scoped("rot-happy-hour")

local function today()
	return os.date("%Y%m%d")
end

local function broadcast(text)
	Game.broadcastMessage(text, MESSAGE_GAME_HIGHLIGHT)
end

-- { kind = "exp"|"loot", until_ = timestamp } o nil
function HH.active()
	local active = store:get("active")
	if type(active) ~= "table" or not active.until_ or active.until_ <= os.time() then
		return nil
	end
	return active
end

function HH.isActive(kind)
	local active = HH.active()
	return active ~= nil and active.kind == kind
end

function HH.start(kind, seconds, manual)
	seconds = seconds or config.duration
	store:set("active", { kind = kind, until_ = os.time() + seconds })
	broadcast(string.format("[Hora Feliz] \161Empieza la HORA FELIZ de %s! Durante %d minutos todos los jugadores reciben %s. \161A cazar!", LABEL[kind], math.floor(seconds / 60), kind == "exp" and "el doble de experiencia" or "el doble de loot"))
	logger.info("[HappyHour] {} started for {}s{}", kind, seconds, manual and " (manual)" or "")
end

function HH.stop(announce)
	local active = HH.active()
	store:remove("active")
	if active and announce then
		broadcast(string.format("[Hora Feliz] Se acab\243 la hora feliz de %s. \161Gracias por participar!", LABEL[active.kind]))
	end
end

-- Plan del dia: { date = "YYYYMMDD", events = { { at = timestamp, kind, warned, started, ended }, ... } }
local function buildPlan()
	local kinds = { unpack(config.kinds) }
	-- Baraja los tipos para que cada dia haya una de cada en orden aleatorio
	for i = #kinds, 2, -1 do
		local j = math.random(i)
		kinds[i], kinds[j] = kinds[j], kinds[i]
	end
	local now = os.date("*t")
	local events = {}
	for index, slot in ipairs(config.slots) do
		local minute = math.random(slot.fromHour * 60, slot.toHour * 60 - 1)
		local at = os.time({ year = now.year, month = now.month, day = now.day, hour = math.floor(minute / 60), min = minute % 60, sec = 0 })
		events[#events + 1] = { at = at, kind = kinds[(index - 1) % #kinds + 1], warned = false, started = false, ended = false }
	end
	return { date = today(), events = events }
end

local function getPlan()
	local plan = store:get("plan")
	if type(plan) ~= "table" or plan.date ~= today() then
		plan = buildPlan()
		store:set("plan", plan)
		for _, event in ipairs(plan.events) do
			logger.info("[HappyHour] planned {} at {}", event.kind, os.date("%H:%M", event.at))
		end
	end
	return plan
end

local function tick()
	local now = os.time()
	local plan = getPlan()
	local changed = false
	local active = HH.active()

	for _, event in ipairs(plan.events) do
		if not event.warned and now >= event.at - config.warning and now < event.at then
			event.warned = true
			changed = true
			broadcast(string.format("[Hora Feliz] \161Atenci\243n! En %d minutos empieza una HORA FELIZ de %s. \161Prep\225rate!", math.ceil((event.at - now) / 60), LABEL[event.kind]))
		end
		if not event.started and now >= event.at and now < event.at + config.duration then
			event.started = true
			event.warned = true
			changed = true
			if not active then
				HH.start(event.kind, event.at + config.duration - now)
				active = HH.active()
			end
		end
		if event.started and not event.ended and now >= event.at + config.duration then
			event.ended = true
			changed = true
		end
	end
	if changed then
		store:set("plan", plan)
	end

	-- Cierre de la hora feliz activa (tanto programada como manual)
	local stored = store:get("active")
	if type(stored) == "table" and stored.until_ and stored.until_ <= now then
		HH.stop(true)
	end
end

local think = GlobalEvent("RoTHappyHourThink")
function think.onThink(interval)
	tick()
	return true
end
think:interval(30 * 1000)
think:register()

local startup = GlobalEvent("RoTHappyHourStartup")
function startup.onStartup()
	getPlan()
	return true
end
startup:register()

-- Experiencia doble
local expCallback = EventCallback("RoTHappyHourExp")
function expCallback.playerOnGainExperience(player, target, exp, rawExp)
	if exp > 0 and HH.isActive("exp") then
		exp = exp * 2
	end
	return exp
end
expCallback:register()

-- Loot doble: una tirada extra de loot, igual que la criatura potenciada
local lootCallback = EventCallback("RoTHappyHourLoot")
function lootCallback.monsterOnDropLoot(monster, corpse)
	if not monster or not corpse or not HH.isActive("loot") then
		return
	end
	local mType = monster:getType()
	if not mType or mType:isRewardBoss() then
		return
	end
	local player = Player(corpse:getCorpseOwner())
	if not player or not player:canReceiveLoot() then
		return
	end
	local existing = corpse:getAttribute(ITEM_ATTRIBUTE_LOOTMESSAGE_SUFFIX) or ""
	corpse:addLoot(mType:generateLootRoll({ factor = 1.0, gut = false }, {}, player))
	corpse:setAttribute(ITEM_ATTRIBUTE_LOOTMESSAGE_SUFFIX, existing .. (#existing > 0 and ", hora feliz" or "hora feliz"))
end
lootCallback:register()

local login = CreatureEvent("RoTHappyHourLogin")
function login.onLogin(player)
	local active = HH.active()
	if active then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("[Hora Feliz] \161Hay una HORA FELIZ de %s activa! Quedan %d minutos.", LABEL[active.kind], math.ceil((active.until_ - os.time()) / 60)))
	end
	return true
end
login:register()

local command = TalkAction("/horafeliz")
function command.onSay(player, words, param)
	local action, minutes = param:trim():match("^(%a+)%s*(%d*)$")
	if action == "exp" or action == "loot" then
		HH.start(action, (tonumber(minutes) or 60) * 60, true)
	elseif action == "stop" then
		HH.stop(true)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Hora feliz detenida.")
	else
		local plan = getPlan()
		local lines = {}
		for _, event in ipairs(plan.events) do
			lines[#lines + 1] = string.format("%s %s%s", os.date("%H:%M", event.at), event.kind, event.ended and " (terminada)" or event.started and " (en curso)" or "")
		end
		local active = HH.active()
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Hora feliz de hoy: %s. Activa ahora: %s.\nUso: /horafeliz exp|loot [minutos], /horafeliz stop", table.concat(lines, ", "), active and (active.kind .. " hasta " .. os.date("%H:%M", active.until_)) or "ninguna"))
	end
	return true
end
command:separator(" ")
command:groupType("god")
command:register()
