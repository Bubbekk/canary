local config = {
	outfits = {},
	mounts = {},
}

function Player.onRemoveVip(self)
	self:sendTextMessage(MESSAGE_ADMINISTRATOR, "Tu estado VIP ha expirado. Se han retirado todos los beneficios VIP.")

	for _, outfit in ipairs(config.outfits) do
		self:removeOutfit(outfit)
	end

	for _, mount in ipairs(config.mounts) do
		self:removeMount(mount)
	end

	local playerOutfit = self:getOutfit()
	if table.contains(config.outfits, playerOutfit.lookType) then
		if self:getSex() == PLAYERSEX_FEMALE then
			playerOutfit.lookType = 136
		else
			playerOutfit.lookType = 128
		end
		playerOutfit.lookAddons = 0

		self:setOutfit(playerOutfit)
	end

	self:kv():scoped("account"):remove("vip-system")
end

function Player.onAddVip(self, days, silent)
	if not silent then
		-- Textos en Latin-1 (\225 = á, \237 = í, \243 = ó) porque el cliente trabaja en cp1252
		if (tonumber(days) or 0) >= 1 then
			self:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Se te han otorgado %s d\237a(s) de estado VIP.", days))
		else
			self:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Tu estado VIP est\225 activo.")
		end
	end

	for _, outfit in ipairs(config.outfits) do
		self:addOutfitAddon(outfit, 3)
	end

	for _, mount in ipairs(config.mounts) do
		self:addMount(mount)
	end

	self:kv():scoped("account"):set("vip-system", true)
end

-- "2 días, 3 horas y 15 minutos" (Latin-1)
local function formatVipTimeRemaining(endTime)
	local seconds = math.max(0, endTime - os.time())
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local parts = {}
	if days > 0 then
		parts[#parts + 1] = days .. (days == 1 and " d\237a" or " d\237as")
	end
	if hours > 0 then
		parts[#parts + 1] = hours .. (hours == 1 and " hora" or " horas")
	end
	if minutes > 0 or #parts == 0 then
		parts[#parts + 1] = minutes .. (minutes == 1 and " minuto" or " minutos")
	end
	if #parts == 1 then
		return parts[1]
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " y " .. parts[#parts]
end

function Player.sendVipStatus(self)
	if self:getVipDays() == 0xFFFF then
		self:sendTextMessage(MESSAGE_LOGIN, "Tienes estado VIP ilimitado.")
		return true
	end

	local playerVipTime = self:getVipTime()
	if playerVipTime < os.time() then
		self:sendTextMessage(MESSAGE_STATUS, "Tu estado VIP est\225 inactivo.")
		return true
	end

	self:sendTextMessage(MESSAGE_LOGIN, string.format("Tiempo VIP restante: %s.", formatVipTimeRemaining(playerVipTime)))
end
