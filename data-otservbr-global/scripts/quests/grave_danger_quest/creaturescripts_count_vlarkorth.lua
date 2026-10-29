local config = {
	centerRoom = Position(33456, 31437, 13),
	newPosition = Position(33457, 31442, 13),
	exitPos = Position(33195, 31696, 8),
	x = 10,
	y = 10,
	summons = {
		[1] = { summon = "Dark Sorcerer" },
		[2] = { summon = "Dark Druid" },
		[3] = { summon = "Dark Paladin" },
		[4] = { summon = "Dark Knight" },
	},
	timer = Storage.Quest.U12_20.GraveDanger.Bosses.CountVlarkorth.Timer,
	room = Storage.Quest.U12_20.GraveDanger.Bosses.CountVlarkorth.Room,
}

-- Monsters have no storage values (only players do): the old code raised an error on every hit, so the
-- boss never summoned its darks and was a punching bag (#3506). Damage is tracked here, and the boss is
-- shielded while any of its darks is alive.
local damageTaken = {}
local darkNames = { ["dark sorcerer"] = true, ["dark druid"] = true, ["dark paladin"] = true, ["dark knight"] = true }

local function countDarks()
	local darks = 0
	for _, spectator in ipairs(Game.getSpectators(config.centerRoom, false, false, config.x, config.x, config.y, config.y)) do
		if spectator:isMonster() and darkNames[spectator:getName():lower()] then
			darks = darks + 1
		end
	end
	return darks
end

local function summonDarks()
	local spectators = Game.getSpectators(config.centerRoom, false, true, config.x, config.x, config.y, config.y)
	local boss = Creature("Count Vlarkorth")
	if not boss then
		return false
	end

	if #spectators > 0 then
		for _, player in pairs(spectators) do
			local vocationId = player:getVocation():getBase():getId()
			local toSummon = config.summons[vocationId]
			if toSummon then
				local newPosition = boss:getClosestFreePosition(boss:getPosition(), true)
				if newPosition then
					Game.createMonster(toSummon.summon, newPosition, false, true)
				end
			end
		end
		boss:say("Face your own darkness!")
	end

	return true
end

local count_vlarkorth_transform = CreatureEvent("count_vlarkorth_transform")

function count_vlarkorth_transform.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local players = Game.getSpectators(config.centerRoom, false, true, config.x, config.x, config.y, config.y)
	for _, player in pairs(players) do
		if player:isPlayer() then
			if player:getStorageValue(config.timer) < os.time() then
				player:setStorageValue(config.timer, os.time() + 20 * 3600)
			end
			if player:getStorageValue(config.room) < os.time() then
				player:setStorageValue(config.room, os.time() + 30 * 60)
			end
		end
	end

	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end

	if not creature then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end

	local health = creature:getMaxHealth() * 0.15
	if countDarks() > 0 then
		creature:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
		return 0, primaryType, 0, secondaryType
	end

	local creatureId = creature:getId()
	damageTaken[creatureId] = (damageTaken[creatureId] or 0) + primaryDamage + secondaryDamage
	if damageTaken[creatureId] >= health then
		damageTaken[creatureId] = 0
		summonDarks()
	end

	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

count_vlarkorth_transform:register()
