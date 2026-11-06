-- RoT Saturday boss event: every Saturday at 15:00 and 20:00 a random boss (any
-- difficulty, different from the previous one) appears at the event position for
-- up to 4 hours. Killing it ends the event; if nobody kills it, it is removed.
local config = {
	position = Position(32252, 32178, 12),
	duration = 4 * 60 * 60 * 1000,
	weekday = 7, -- os.date wday: 7 = Saturday
}

local bosses = {
	"Abyssador",
	"Alptramun",
	"Amenef the Burning",
	"Ancient Spawn of Morgathla",
	"Annihilon",
	"Anomaly",
	"Arbaziloth",
	"Ashmunrah",
	"Bakragore",
	"Bibby Bloodbath",
	"Black Knight",
	"Black Vixen",
	"Bloodback",
	"Bragrumol",
	"Brain Head",
	"Brokul",
	"Bullwark",
	"Chagorz",
	"Chikhaton",
	"Count Vlarkorth",
	"Countess Sorrow",
	"Custodian",
	"Darkfang",
	"Dazed Leaf Golem",
	"Death Priest Shargon",
	"Deathstrike",
	"Deep Terror",
	"Diblis the Fair",
	"Dipthrah",
	"Diseased Bill",
	"Diseased Fred",
	"Dracola",
	"Dreadful Disruptor",
	"Drume",
	"Duke Krule",
	"Earl Osam",
	"Eradicator",
	"Essence of Malice",
	"Evil Mastermind",
	"Faceless Bane",
	"Feroxa",
	"Fleshslicer",
	"Gaffir",
	"Gaz'Haragoth",
	"Gelidrazah the Frozen",
	"Ghulosh",
	"Glitterscale",
	"Gnomevil",
	"Golgordan",
	"Gorzindel",
	"Goshnar's Cruelty",
	"Goshnar's Greed",
	"Goshnar's Hatred",
	"Goshnar's Malice",
	"Goshnar's Spite",
	"Grand Canon Dominus",
	"Grand Chaplain Gaunder",
	"Grand Commander Soeren",
	"Grand Master Oberon",
	"Grandfather Tridian",
	"Gravelord Oshuran",
	"Guard Captain Quaid",
	"Hellgorak",
	"Horestis",
	"Ichgahal",
	"Irgix The Flimsy",
	"Izcandar the Banished",
	"Jaul",
	"Kalyassa",
	"Katex Blood Tongue",
	"King Zelos",
	"Kroazur",
	"Lady Tenebris",
	"Latrivan",
	"Lisa",
	"Lloyd",
	"Lokathmor",
	"Lord Azaram",
	"Lord of the Elements",
	"Mad Mage",
	"Madareth",
	"Mahrdis",
	"Malofur Mangrinder",
	"Massacre",
	"Maxxenius",
	"Mazoran",
	"Mazzinor",
	"Megasylvan Yselda",
	"Mitmah Vanguard",
	"Morguthis",
	"Morshabaal",
	"Mozradek",
	"Mr. Punish",
	"Murcion",
	"Neferi the Spy",
	"Obujos",
	"Omrafir",
	"Omruc",
	"Outburst",
	"Plagirath",
	"Plagueroot",
	"Preceptor Lazare",
	"Professor Maxxen",
	"Ragiaz",
	"Raging mage",
	"Rahemos",
	"Ratmiral Blackwhiskers",
	"Ravenous Hunger",
	"Raxias",
	"Razzagorn",
	"Realityquake",
	"Rupture",
	"Scarlett Etzel",
	"Sharpclaw",
	"Shulgrax",
	"Sir Baeloc",
	"Sir Nictros",
	"Sister Hetai",
	"Soul of Dragonking Zyrtarch",
	"Srezz Yellow Eyes",
	"Sugar Daddy",
	"Sugar Mommy",
	"Tanjis",
	"Tarbaz",
	"Tazhadur",
	"Thalas",
	"Thawing Dragon Lord",
	"The Abomination",
	"The Baron from Below",
	"The Blazing Rose",
	"The Brainstealer",
	"The Count of the Core",
	"The Diamond Blossom",
	"The Dread Maiden",
	"The Duke of the Depths",
	"The Enraged Thorn Knight",
	"The Evil Eye",
	"The False God",
	"The Fear Feaster",
	"The First Dragon",
	"The Handmaiden",
	"The Imperor",
	"The Last Lore Keeper",
	"The Lily of Night",
	"The Lord of the Lice",
	"The Monster",
	"The Nightmare Beast",
	"The Pale Worm",
	"The Percht Queen",
	"The Plasmother",
	"The Ravager",
	"The Rootkraken",
	"The Sandking",
	"The Shatterer",
	"The Souldespoiler",
	"The Unwelcome",
	"Timira the Many-Headed",
	"Unaz the Mean",
	"Urmahlullu the Immaculate",
	"Ushuriel",
	"Utua Stone Sting",
	"Vashresamun",
	"Vemiath",
	"Vok the Freakish",
	"Warlord Ruzad",
	"World Devourer",
	"Xogixath",
	"Yirkas Blue Scales",
	"Zamulosh",
	"Zarabustor",
	"Zevelon Duskbringer",
	"Zorvorax",
	"Zugurosh",
	"Zushuka",
}

-- Active event state. The token invalidates stale timers after a kill or a new event.
local state = { token = 0, bossId = nil, bossName = nil, lastBossName = nil }

local function broadcast(message)
	Game.broadcastMessage(message, MESSAGE_GAME_HIGHLIGHT)
end

local function endEvent(token)
	if state.token ~= token or not state.bossId then
		return
	end
	local boss = Monster(state.bossId)
	if boss then
		boss:getPosition():sendMagicEffect(CONST_ME_POFF)
		boss:remove()
	end
	broadcast(string.format("[Boss Event] Time is up! %s has escaped. The boss event has ended.", state.bossName))
	state.bossId = nil
	state.token = state.token + 1
end

local function startEvent()
	if state.bossId and Monster(state.bossId) then
		return -- previous boss still alive
	end

	local pool = {}
	for _, name in ipairs(bosses) do
		if name ~= state.lastBossName and MonsterType(name) then
			pool[#pool + 1] = name
		end
	end
	for _ = 1, 10 do
		if #pool == 0 then
			break
		end
		local index = math.random(#pool)
		local name = pool[index]
		local boss = Game.createMonster(name, config.position, true, true)
		if boss then
			state.token = state.token + 1
			state.bossId = boss:getId()
			state.bossName = boss:getName()
			state.lastBossName = name
			boss:registerEvent("RoTBossEventDeath")
			boss:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			broadcast(string.format("[Boss Event] %s has appeared beneath Thais! The boss event is active for 4 hours. Defeat it before it escapes!", state.bossName))
			logger.info("[RoTBossEvent] spawned {}", state.bossName)
			addEvent(endEvent, config.duration, state.token)
			return
		end
		table.remove(pool, index)
	end
	logger.warn("[RoTBossEvent] could not spawn any boss")
end

local bossDeath = CreatureEvent("RoTBossEventDeath")
function bossDeath.onDeath(creature, corpse, killer, mostDamageKiller)
	if not state.bossId or creature:getId() ~= state.bossId then
		return true
	end
	local killerName = mostDamageKiller and mostDamageKiller:getName() or (killer and killer:getName())
	if killerName then
		broadcast(string.format("[Boss Event] %s has been defeated by %s! The boss event has ended.", state.bossName, killerName))
	else
		broadcast(string.format("[Boss Event] %s has been defeated! The boss event has ended.", state.bossName))
	end
	state.bossId = nil
	state.token = state.token + 1 -- cancels the pending timeout
	return true
end
bossDeath:register()

for _, hour in ipairs({ "15:00", "20:00" }) do
	local event = GlobalEvent("RoTBossEvent" .. hour:gsub(":", ""))
	function event.onTime(interval)
		if os.date("*t").wday == config.weekday then
			startEvent()
		end
		return true
	end
	event:time(hour)
	event:register()
end

-- GOD command to start the event manually (for testing): /bossevent
local bossEventCommand = TalkAction("/bossevent")
function bossEventCommand.onSay(player, words, param)
	startEvent()
	return true
end
bossEventCommand:groupType("god")
bossEventCommand:register()
