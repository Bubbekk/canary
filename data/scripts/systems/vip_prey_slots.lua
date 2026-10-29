-- Las cuentas VIP tienen desbloqueado el tercer espacio de Prey y la Expansión de Weekly Tasks del Taskboard.
-- Al dejar de ser VIP se vuelven a bloquear, pero SOLO si los desbloqueó el VIP
-- (si el jugador los compró en la Tienda, se respetan). Se revisa en cada inicio de sesión.

local slots = {
	{ key = "vip-prey-third-slot", get = function(p) return p:preyThirdSlot() end, set = function(p, v) return p:preyThirdSlot(v) end },
	-- En clientes 15.20+ las Hunting Tasks se sustituyeron por el Taskboard; su equivalente es la Expansión de Weekly Tasks
	{ key = "vip-weekly-expansion", get = function(p)
		local tb = rawget(_G, "Taskboard")
		if type(tb) ~= "table" or type(tb.expansion) ~= "table" then
			return nil
		end
		local ok, unlocked = pcall(tb.expansion.isUnlocked, p)
		if not ok then
			return nil
		end
		return unlocked == true
	end, set = function(p, v)
		local tb = rawget(_G, "Taskboard")
		if type(tb) == "table" and type(tb.expansion) == "table" then
			pcall(tb.expansion.setUnlocked, p, v)
		end
	end },
}

local vipPreySlots = CreatureEvent("VipPreySlotsLogin")

function vipPreySlots.onLogin(player)
	local isVip = configManager.getBoolean(configKeys.VIP_SYSTEM_ENABLED) and player:isVip()
	for _, slot in ipairs(slots) do
		local unlocked = slot.get(player)
		if unlocked ~= nil then
			local grantedByVip = player:kv():get(slot.key) == true
			if isVip and not unlocked then
				slot.set(player, true)
				player:kv():set(slot.key, true)
			elseif not isVip and grantedByVip then
				if unlocked then
					slot.set(player, false)
				end
				player:kv():remove(slot.key)
			end
		end
	end
	return true
end

vipPreySlots:register()
