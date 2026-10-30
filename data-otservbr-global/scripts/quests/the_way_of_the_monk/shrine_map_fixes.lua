-- Runtime map patch for upstream issue #4057: wall pieces block the climb routes to the
-- Respect (Tyrsung) and Eternity (Kilmaresh) shrines, and the Serenity (Barkless) door is a
-- locked door with no actionid that no key can open. Each fix only touches the exact item
-- expected on that tile, so it becomes a no-op once the source map is corrected.
local blockingPieces = {
	-- Respect (Tyrsung)
	{ Position(32412, 31280, 6), 6720 },
	{ Position(32413, 31280, 6), 6723 },
	{ Position(32413, 31279, 6), 6724 },
	{ Position(32412, 31279, 5), 6723 },
	{ Position(32412, 31278, 5), 6724 },
	{ Position(32413, 31278, 5), 6723 },
	{ Position(32413, 31277, 5), 6724 },
	{ Position(32414, 31277, 5), 6723 },
	{ Position(32412, 31277, 4), 6723 },
	{ Position(32412, 31276, 4), 6724 },
	{ Position(32413, 31276, 4), 6723 },
	-- Eternity (Kilmaresh)
	{ Position(33843, 31623, 4), 6719 },
	{ Position(33843, 31624, 4), 6723 },
}

local serenityDoor = { position = Position(32767, 31525, 9), lockedId = 5124, closedId = 5125 }

local shrineMapFixes = GlobalEvent("MonkShrineMapFixes")

function shrineMapFixes.onStartup()
	local removed = 0
	for _, entry in ipairs(blockingPieces) do
		local tile = Tile(entry[1])
		local item = tile and tile:getItemById(entry[2])
		if item then
			item:remove()
			removed = removed + 1
		end
	end

	local doorFixed = 0
	local doorTile = Tile(serenityDoor.position)
	local door = doorTile and doorTile:getItemById(serenityDoor.lockedId)
	if door and door.actionid == 0 then
		door:transform(serenityDoor.closedId)
		doorFixed = 1
	end

	logger.info("[MonkShrineMapFixes] Removed {}/{} blocking pieces, fixed {} Serenity door", removed, #blockingPieces, doorFixed)
	return true
end

shrineMapFixes:register()
