local internalNpcName = "Lorenzo"
local npcType = Game.createNpcType(internalNpcName)
local npcConfig = {}

npcConfig.name = internalNpcName
npcConfig.description = internalNpcName

npcConfig.health = 150
npcConfig.maxHealth = npcConfig.health
npcConfig.walkInterval = 2000
npcConfig.walkRadius = 2

npcConfig.outfit = {
	lookType = 128,
	lookHead = 95,
	lookBody = 38,
	lookLegs = 76,
	lookFeet = 114,
	lookAddons = 3,
}

npcConfig.flags = {
	floorchange = false,
	profession = "sailor",
}
npcConfig.speechBubble = SPEECHBUBBLE_TRADE

local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)

npcType.onThink = function(npc, interval)
	npcHandler:onThink(npc, interval)
end

npcType.onAppear = function(npc, creature)
	npcHandler:onAppear(npc, creature)
end

npcType.onDisappear = function(npc, creature)
	npcHandler:onDisappear(npc, creature)
end

npcType.onMove = function(npc, creature, fromPosition, toPosition)
	npcHandler:onMove(npc, creature, fromPosition, toPosition)
end

npcType.onSay = function(npc, creature, type, message)
	npcHandler:onSay(npc, creature, type, message)
end

npcType.onCloseChannel = function(npc, creature)
	npcHandler:onCloseChannel(npc, creature)
end

-- RoT: rings, amulets, ammunition and imbuement materials.
npcConfig.shop = {
	{ itemName = "might ring", clientId = 3048, buy = 25000 },
	{ itemName = "time ring", clientId = 3053, buy = 5000 },
	{ itemName = "energy ring", clientId = 3051, buy = 5000 },
	{ itemName = "life ring", clientId = 3052, buy = 900 },
	{ itemName = "ring of healing", clientId = 3098, buy = 2000 },
	{ itemName = "stealth ring", clientId = 3049, buy = 5000 },
	{ itemName = "dwarven ring", clientId = 3097, buy = 3000 },
	{ itemName = "power ring", clientId = 3050, buy = 100 },
	{ itemName = "stone skin amulet", clientId = 3081, buy = 25000 },
	{ itemName = "platinum amulet", clientId = 3055, buy = 3750 },
	{ itemName = "garlic necklace", clientId = 3083, buy = 100 },
	{ itemName = "elven amulet", clientId = 3082, buy = 500 },
	{ itemName = "dragon necklace", clientId = 3085, buy = 1000 },
	{ itemName = "protection amulet", clientId = 3084, buy = 700 },
	{ itemName = "arrow", clientId = 3447, buy = 3 },
	{ itemName = "bolt", clientId = 3446, buy = 5 },
	{ itemName = "power bolt", clientId = 3450, buy = 7 },
	{ itemName = "onyx arrow", clientId = 7365, buy = 7 },
	{ itemName = "sniper arrow", clientId = 7364, buy = 5 },
	{ itemName = "piercing bolt", clientId = 7363, buy = 5 },
	{ itemName = "infernal bolt", clientId = 6528, buy = 13 },
	{ itemName = "crystalline arrow", clientId = 15793, buy = 450 },
	{ itemName = "prismatic bolt", clientId = 16141, buy = 20 },
	{ itemName = "diamond arrow", clientId = 35901, buy = 130 },
	{ itemName = "spectral bolt", clientId = 35902, buy = 70 },
	{ itemName = "spear", clientId = 3277, buy = 10 },
	{ itemName = "royal spear", clientId = 7378, buy = 100 },
	{ itemName = "enchanted spear", clientId = 7367, buy = 40 },
	{ itemName = "assassin star", clientId = 7368, buy = 100 },
	{ itemName = "green dragon leather", clientId = 5877, buy = 150 },
	{ itemName = "green dragon scale", clientId = 5920, buy = 150 },
	{ itemName = "demon horn", clientId = 5954, buy = 1500 },
	{ itemName = "bloody pincers", clientId = 9633, buy = 150 },
	{ itemName = "elvish talisman", clientId = 9635, buy = 68 },
	{ itemName = "fiery heart", clientId = 9636, buy = 563 },
	{ itemName = "cultish mask", clientId = 9638, buy = 420 },
	{ itemName = "cultish robe", clientId = 9639, buy = 225 },
	{ itemName = "poisonous slime", clientId = 9640, buy = 75 },
	{ itemName = "piece of scarab shell", clientId = 9641, buy = 68 },
	{ itemName = "wyvern talisman", clientId = 9644, buy = 398 },
	{ itemName = "demonic skeletal hand", clientId = 9647, buy = 120 },
	{ itemName = "polar bear paw", clientId = 9650, buy = 45 },
	{ itemName = "war crystal", clientId = 9654, buy = 690 },
	{ itemName = "cyclops toe", clientId = 9657, buy = 83 },
	{ itemName = "mystical hourglass", clientId = 9660, buy = 1050 },
	{ itemName = "frosty heart", clientId = 9661, buy = 420 },
	{ itemName = "piece of dead brain", clientId = 9663, buy = 630 },
	{ itemName = "wyrm scale", clientId = 9665, buy = 600 },
	{ itemName = "vampire teeth", clientId = 9685, buy = 413 },
	{ itemName = "swamp grass", clientId = 9686, buy = 30 },
	{ itemName = "ghostly tissue", clientId = 9690, buy = 135 },
	{ itemName = "lion's mane", clientId = 9691, buy = 90 },
	{ itemName = "snake skin", clientId = 9694, buy = 600 },
	{ itemName = "orc tooth", clientId = 10196, buy = 225 },
	{ itemName = "tarantula egg", clientId = 10281, buy = 120 },
	{ itemName = "winter wolf fur", clientId = 10295, buy = 30 },
	{ itemName = "metal spike", clientId = 10298, buy = 480 },
	{ itemName = "compass", clientId = 10302, buy = 68 },
	{ itemName = "hellspawn tail", clientId = 10304, buy = 713 },
	{ itemName = "thick fur", clientId = 10307, buy = 225 },
	{ itemName = "strand of medusa hair", clientId = 10309, buy = 900 },
	{ itemName = "sabretooth", clientId = 10311, buy = 600 },
	{ itemName = "warmaster's wristguards", clientId = 10405, buy = 300 },
	{ itemName = "petrified scream", clientId = 10420, buy = 375 },
	{ itemName = "protective charm", clientId = 11444, buy = 90 },
	{ itemName = "battle stone", clientId = 11447, buy = 435 },
	{ itemName = "broken shamanic staff", clientId = 11452, buy = 53 },
	{ itemName = "elven scouting glass", clientId = 11464, buy = 75 },
	{ itemName = "flask of embalming fluid", clientId = 11466, buy = 45 },
	{ itemName = "pile of grave earth", clientId = 11484, buy = 38 },
	{ itemName = "mantassin tail", clientId = 11489, buy = 420 },
	{ itemName = "rope belt", clientId = 11492, buy = 99 },
	{ itemName = "draken sulphur", clientId = 11658, buy = 825 },
	{ itemName = "brimstone fangs", clientId = 11702, buy = 570 },
	{ itemName = "brimstone shell", clientId = 11703, buy = 315 },
	{ itemName = "deepling warts", clientId = 14012, buy = 270 },
	{ itemName = "crawler head plating", clientId = 14079, buy = 315 },
	{ itemName = "waspoid wing", clientId = 14081, buy = 285 },
	{ itemName = "blazing bone", clientId = 16131, buy = 915 },
	{ itemName = "damselfly wing", clientId = 17458, buy = 30 },
	{ itemName = "piece of swampling wood", clientId = 17823, buy = 45 },
	{ itemName = "rorc feather", clientId = 18993, buy = 105 },
	{ itemName = "elven hoof", clientId = 18994, buy = 173 },
	{ itemName = "frazzle skin", clientId = 20199, buy = 600 },
	{ itemName = "silencer claws", clientId = 20200, buy = 585 },
	{ itemName = "goosebump leather", clientId = 20205, buy = 975 },
	{ itemName = "slime heart", clientId = 21194, buy = 240 },
	{ itemName = "moohtant horn", clientId = 21200, buy = 210 },
	{ itemName = "mooh'tah shell", clientId = 21202, buy = 165 },
	{ itemName = "seacrest hair", clientId = 21801, buy = 390 },
	{ itemName = "peacock feather fan", clientId = 21975, buy = 525 },
	{ itemName = "gloom wolf fur", clientId = 22007, buy = 105 },
	{ itemName = "wereboar hooves", clientId = 22053, buy = 263 },
	{ itemName = "ogre nose ring", clientId = 22189, buy = 315 },
	{ itemName = "vexclaw talon", clientId = 22728, buy = 1650 },
	{ itemName = "some grimeleech wings", clientId = 22730, buy = 1800 },
	{ itemName = "crystallized anger", clientId = 23507, buy = 600 },
	{ itemName = "energy vein", clientId = 23508, buy = 405 },
	{ itemName = "fairy wings", clientId = 25694, buy = 300 },
	{ itemName = "little bowl of myrrh", clientId = 25702, buy = 750 },
	{ itemName = "quill", clientId = 28567, buy = 1650 },
	{ itemName = "gold-brocaded cloth", clientId = 40529, buy = 263 },
}
-- On buy npc shop message
npcType.onBuyItem = function(npc, player, itemId, subType, amount, ignore, inBackpacks, totalCost)
	npc:sellItem(player, itemId, amount, subType, 0, ignore, inBackpacks)
end
-- On sell npc shop message
npcType.onSellItem = function(npc, player, itemId, subtype, amount, ignore, name, totalCost)
	player:sendTextMessage(MESSAGE_TRADE, string.format("Sold %ix %s for %i gold.", amount, name, totalCost))
end
-- On check npc shop message (look item)
npcType.onCheckItem = function(npc, player, clientId, subType) end

local function creatureSayCallback(npc, creature, type, message)
	if not npcHandler:checkInteraction(npc, creature) then
		return false
	end
	if MsgContains(message, "name") then
		npcHandler:say("I am Lorenzo, supplier of adventurers.", npc, creature)
	elseif MsgContains(message, "job") or MsgContains(message, "offer") then
		npcHandler:say("I sell rings, amulets, ammunition and imbuement materials. Ask me for a {trade}.", npc, creature)
	end
	return true
end

npcHandler:setMessage(MESSAGE_GREET, "Welcome, |PLAYERNAME|! I have rings, amulets, ammunition and imbuement materials. Just ask for a {trade}.")
npcHandler:setMessage(MESSAGE_FAREWELL, "Good hunting, |PLAYERNAME|!")
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new(), npcConfig.name, true, true, true)

npcType:register(npcConfig)
