-- Allows a single online character per IP address. Staff (account access) are exempt.
local onePlayerPerIp = CreatureEvent("OnePlayerPerIp")

function onePlayerPerIp.onLogin(player)
	if player:getGroup():getAccess() then
		return true
	end

	local ip = player:getIp()
	if ip == 0 then
		return true
	end

	for _, other in ipairs(Game.getPlayers()) do
		if other:getId() ~= player:getId() and other:getIp() == ip and not other:getGroup():getAccess() then
			player:popupFYI("Solo se permite un personaje conectado por IP.\nYa hay otro personaje en l\237nea desde tu conexi\243n.")
			return false
		end
	end
	return true
end

onePlayerPerIp:register()
