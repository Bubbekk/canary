local requiredItems = { 283, 284, 285 }

local transformations = {
	{ fromItemId = 25879, toItemId = 266 },
	{ fromItemId = 25880, toItemId = 236 },
	{ fromItemId = 25881, toItemId = 239 },
	{ fromItemId = 25882, toItemId = 7643 },
	{ fromItemId = 25883, toItemId = 23375 },
	{ fromItemId = 25889, toItemId = 268 },
	{ fromItemId = 25890, toItemId = 237 },
	{ fromItemId = 25891, toItemId = 238 },
	{ fromItemId = 25892, toItemId = 23373 },
	{ fromItemId = 25899, toItemId = 7642 },
	{ fromItemId = 25900, toItemId = 23374 },
	{ fromItemId = 25903, toItemId = 266 },
	{ fromItemId = 25904, toItemId = 236 },
	{ fromItemId = 25905, toItemId = 239 },
	{ fromItemId = 25906, toItemId = 7643 },
	{ fromItemId = 25907, toItemId = 23375 },
	{ fromItemId = 25908, toItemId = 268 },
	{ fromItemId = 25909, toItemId = 237 },
	{ fromItemId = 25910, toItemId = 238 },
	{ fromItemId = 25911, toItemId = 23373 },
	{ fromItemId = 25913, toItemId = 7642 },
	{ fromItemId = 25914, toItemId = 23374 },
}

-- Las pociones de barriles y toneles se crean en el buzón de la Tienda y marcadas como objeto
-- de la Tienda (no se pueden vender ni intercambiar), tal como indica su descripción en la Tienda.
-- Antes se creaban en el inventario como pociones normales y podían revenderse.
-- Devuelve cuántas pociones se crearon (puede ser menos si el buzón se llena).
local function addStorePotions(inbox, potionId, amount)
	local stackSize = math.max(1, ItemType(potionId):getStackSize())
	local created = 0
	while created < amount do
		local chunk = math.min(stackSize, amount - created)
		local potion = inbox:addItem(potionId, chunk)
		if not potion then
			break
		end
		potion:setAttribute(ITEM_ATTRIBUTE_STORE, systemTime())
		created = created + chunk
	end
	return created
end

-- Textos en Latin-1 (\243 = ó, \237 = í) porque el cliente trabaja en cp1252
local function processTransformation(player, item, charges, transformation)
	local transformedCount = 0

	if charges <= 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Este objeto no tiene cargas.")
		return false
	end

	local inbox = player:getStoreInbox()
	if not inbox then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "No se encontr\243 tu buz\243n de la Tienda.")
		return false
	end

	local inboxFull = false
	for _, requiredItemId in ipairs(requiredItems) do
		local itemCount = player:getItemCount(requiredItemId)

		if itemCount > 0 then
			local transformable = math.min(itemCount, charges - transformedCount)

			if transformable > 0 then
				-- Primero se crean las pociones; solo se retiran los frascos que se convirtieron
				local created = addStorePotions(inbox, transformation.toItemId, transformable)
				if created > 0 then
					player:removeItem(requiredItemId, created)
					transformedCount = transformedCount + created
				end

				if created < transformable then
					inboxFull = true
					break
				end

				if transformedCount >= charges then
					break
				end
			end
		end
	end

	if transformedCount > 0 then
		local newCharges = charges - transformedCount

		if newCharges > 0 then
			item:setAttribute(ITEM_ATTRIBUTE_CHARGES, newCharges)
		else
			item:remove(1)
		end

		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Se enviaron %d pociones a tu buz\243n de la Tienda. Cargas restantes: %d", transformedCount, newCharges))
	elseif not inboxFull then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Necesitas frascos vac\237os para llenarlos.")
	end

	if inboxFull then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Tu buz\243n de la Tienda est\225 lleno. Libera espacio para seguir llenando pociones.")
	end

	return true
end

local function onUseTransformation(player, item, position, target, toPosition, isHotkey)
	local charges = item:getAttribute(ITEM_ATTRIBUTE_CHARGES) or 0

	for _, transformation in ipairs(transformations) do
		if item:getId() == transformation.fromItemId then
			return processTransformation(player, item, charges, transformation)
		end
	end

	return false
end

for _, transformation in ipairs(transformations) do
	local action = Action()
	action:id(transformation.fromItemId)
	action.onUse = onUseTransformation
	action:register()
end
