local config = {
	centerRoom = Position(33488, 31438, 13),
	newPosition = Position(33489, 31441, 13),
	exitPos = Position(33261, 31985, 8),
	x = 10,
	y = 10,
	timer = Storage.Quest.U12_20.GraveDanger.Bosses.EarlOsam.Timer,
	room = Storage.Quest.U12_20.GraveDanger.Bosses.EarlOsam.Room,
	fromPos = Position(33479, 31429, 13),
	toPos = Position(33497, 31447, 13),
	spheres = {
		Position(33480, 31438, 13),
		Position(33488, 31430, 13),
		Position(33496, 31438, 13),
		Position(33488, 31446, 13),
	},
}

-- Monsters have no storage values (only players do): the old calls raised an error on every hit, so
-- the sphere and shield mechanics never ran (#3506). These keep the same values per monster in memory.
local monsterValues = {}

local function getMonsterValue(monster, key)
	local values = monsterValues[monster:getId()]
	return values and values[key] or -1
end

local function setMonsterValue(monster, key, value)
	local id = monster:getId()
	monsterValues[id] = monsterValues[id] or {}
	monsterValues[id][key] = value
end

local function moveSphere()
	local spectators = Game.getSpectators(config.centerRoom, false, false, config.x, config.x, config.y, config.y)
	local nextPos = nil
	local boss = Creature("Earl Osam")

	if boss and getMonsterValue(boss, 3) > 0 then
		for _, spheres in pairs(spectators) do
			if spheres:isMonster() and spheres:getName():lower() == "magical sphere" then
				local pos = spheres:getPosition()

				if pos.y == 31438 then
					if pos.x > 33488 then
						nextPos = Position(pos.x - 1, pos.y, pos.z)
					elseif pos.x < 33488 then
						nextPos = Position(pos.x + 1, pos.y, pos.z)
					end
				elseif pos.x == 33488 then
					if pos.y > 31438 then
						nextPos = Position(pos.x, pos.y - 1, pos.z)
					elseif pos.y < 31438 then
						nextPos = Position(pos.x, pos.y + 1, pos.z)
					end
				end

				if nextPos then
					local nextTile = Tile(nextPos)
					if nextTile then
						local nextCreature = nextTile:getTopCreature()
						if nextCreature then
							if nextPos == config.centerRoom and nextCreature:getName():lower() == "earl osam" then
								spheres:remove()
								nextCreature:addHealth(80000)
								setMonsterValue(nextCreature, 3, getMonsterValue(nextCreature, 3) - 1)
								if nextCreature:isMoveLocked() then
									nextCreature:setMoveLocked(false)
								end
							else
								spheres:remove()
							end
						else
							spheres:teleportTo(nextPos)
						end
					end
				end
			end
		end

		if boss:getHealth() > 0 then
			addEvent(moveSphere, 4 * 1000)
		end
	end

	return true
end

local function initMech()
	local boss = Creature("Earl Osam")
	if boss then
		local topCenter = Tile(config.centerRoom):getTopCreature()
		if topCenter and topCenter ~= boss then
			topCenter:teleportTo(Position(config.centerRoom.x, config.centerRoom.y + 2, config.centerRoom.z))
		end

		boss:teleportTo(config.centerRoom)
		boss:setMoveLocked(true)

		for _, sphereSpot in pairs(config.spheres) do
			local sphere = Game.createMonster("Magical Sphere", sphereSpot, false, true)
			if sphere then
				setMonsterValue(boss, 3, math.max(0, getMonsterValue(boss, 3)) + 1)
			end
		end

		addEvent(moveSphere, 4 * 1000)
	end

	return true
end

local earl_osam_transform = CreatureEvent("earl_osam_transform")

function earl_osam_transform.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
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

	local chance = math.random(1, 100)
	local position = Position(math.random(config.fromPos.x, config.toPos.x), math.random(config.fromPos.y, config.toPos.y), config.fromPos.z)
	local tile = Tile(position)

	if chance >= 95 and tile and tile:isWalkable() then
		Game.createMonster("Frozen Soul", position)
	end

	local healthThreshold = creature:getMaxHealth() * 0.15
	local currentDamage = getMonsterValue(creature, 1)
	if currentDamage < 0 then
		setMonsterValue(creature, 1, 0)
	end

	if getMonsterValue(creature, 3) > 0 then
		creature:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end

	setMonsterValue(creature, 1, currentDamage + primaryDamage + secondaryDamage)

	if getMonsterValue(creature, 1) >= healthThreshold then
		setMonsterValue(creature, 1, 0)
		setMonsterValue(creature, 3, 0)
		initMech()
	end

	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

earl_osam_transform:register()

local sphere_death = CreatureEvent("sphere_death")

function sphere_death.onDeath(creature)
	local boss = Creature("Earl Osam")
	if boss then
		local currentSphereCount = getMonsterValue(boss, 3)
		setMonsterValue(boss, 3, math.max(0, currentSphereCount - 1))
		if getMonsterValue(boss, 3) <= 0 and boss:isMoveLocked() then
			boss:setMoveLocked(false)
		end
	end
	return true
end

sphere_death:register()
