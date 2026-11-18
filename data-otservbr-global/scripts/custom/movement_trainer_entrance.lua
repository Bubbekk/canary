-- Trainer rooms: every room has a glowing switch where the player stands and two
-- static Training Machine spawns (see otservbr-custom-monster.xml), so this script
-- only has to find a free room. Room X offsets come from the map: the last column
-- is one tile wider than the others.
local config = {
	firstRoomPosition = { x = 1018, y = 1112, z = 7 },
	columnOffsetsX = { 0, 12, 24, 36, 48, 60, 73 },
	distancePositionY = 12,
	lines = 53,
}

local function isFree(position)
	local tile = Tile(position)
	if not tile then
		return false
	end

	local ground = tile:getGround()
	if not ground or ground:hasProperty(CONST_PROP_BLOCKSOLID) then
		return false
	end

	return tile:getCreatureCount() == 0
end

local function findFreeRoom()
	local base = config.firstRoomPosition
	for line = 0, config.lines - 1 do
		for _, offsetX in ipairs(config.columnOffsetsX) do
			local roomPosition = Position(base.x + offsetX, base.y + line * config.distancePositionY, base.z)
			if isFree(roomPosition) then
				return roomPosition
			end
		end
	end
	return nil
end

local trainerEntrance = MoveEvent()
function trainerEntrance.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end

	local roomPosition = findFreeRoom()
	if not roomPosition then
		player:teleportTo(fromPosition, true)
		player:sendCancelMessage("All training rooms are busy right now.")
		return true
	end

	player:teleportTo(roomPosition)
	roomPosition:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

trainerEntrance:position({ x = 1116, y = 1092, z = 7 })
trainerEntrance:register()
