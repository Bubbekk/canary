local iceAntHill = Action()

function iceAntHill.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local mast = { x = 32360, y = 31365, z = 7 }

	if target.itemid == 1079 and item.itemid == 7243 then
		if player:getStorageValue(Storage.Quest.U8_0.TheIceIslands.Questline) == 6 then
			toPosition:sendMagicEffect(CONST_ME_GROUNDSHAKER)
			player:setStorageValue(Storage.Quest.U8_0.TheIceIslands.Mission03, 2) -- Questlog The Ice Islands Quest, Nibelor 2: Ecological Terrorism
			player:say("You fill the jug with ants.", TALKTYPE_MONSTER_SAY)
			item:transform(7244)
		end
	-- The mast exists in several sprites (4940-4952) and only 4940 at one exact tile was accepted, so using
	-- the jug on the mast often did nothing (#3770). Accept any mast piece of the western mast.
	elseif item.itemid == 7244 and target.itemid >= 4940 and target.itemid <= 4952 and toPosition.z == mast.z and math.abs(toPosition.x - mast.x) <= 1 and math.abs(toPosition.y - mast.y) <= 1 then
		if player:getStorageValue(Storage.Quest.U8_0.TheIceIslands.Questline) == 6 then
			toPosition:sendMagicEffect(CONST_ME_HITAREA)
			player:setStorageValue(Storage.Quest.U8_0.TheIceIslands.Questline, 7)
			player:setStorageValue(Storage.Quest.U8_0.TheIceIslands.Mission03, 3) -- Questlog The Ice Islands Quest, Nibelor 2: Ecological Terrorism
			player:say("You released ants on the hill.", TALKTYPE_MONSTER_SAY)
			item:remove(1) -- the full jug (7244); removing 7243 (empty jug) never matched
		end
	end

	return true
end

iceAntHill:id(7243, 7244)
iceAntHill:register()
