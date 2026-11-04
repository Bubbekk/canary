-- Bounty hunting (sicariato): pure rules with no game API, unit tested in tests/lua/test_bounty_core.lua.
-- The game integration lives in data/scripts/systems/bounty.lua.
BountyCore = {}
local Core = BountyCore

Core.config = {
	minReward = 50, -- Tibia coins
	maxReward = 100000,
	feePercent = 10, -- kept by the server on placement, never refunded: makes coin ping-pong between friends cost money
	durations = { 1, 6, 12, 24, 48, 72 }, -- hours a bounty may last
	maxActivePerPlacer = 5,
	minTargetLevel = 50,
	recentHitMs = 60 * 1000, -- only attackers that hit the target in the last minute share the reward
	listSize = 10,
}

function Core.isAllowedDuration(hours)
	for _, value in ipairs(Core.config.durations) do
		if value == hours then
			return true
		end
	end
	return false
end

-- Returns fee, pot for a placed amount
function Core.fee(amount)
	local fee = math.floor(amount * Core.config.feePercent / 100)
	return fee, amount - fee
end

-- args = { amount, hours, placerCoins, placerAccount, targetAccount, targetLevel, targetIsStaff, activeByPlacer }
-- Returns true or false, reason (Spanish, ready for the player)
function Core.validatePlacement(args)
	local config = Core.config
	local amount = args.amount
	if type(amount) ~= "number" or amount ~= math.floor(amount) then
		return false, "La recompensa debe ser un n\250mero entero de Tibia coins."
	end
	if amount < config.minReward or amount > config.maxReward then
		return false, string.format("La recompensa debe estar entre %d y %d Tibia coins.", config.minReward, config.maxReward)
	end
	if not Core.isAllowedDuration(args.hours) then
		return false, "Duraci\243n no permitida."
	end
	if args.targetAccount == nil then
		return false, "Ese personaje no existe."
	end
	if args.targetIsStaff then
		return false, "No puedes poner recompensa por un miembro del staff."
	end
	if args.targetAccount == args.placerAccount then
		return false, "No puedes poner recompensa por un personaje de tu propia cuenta."
	end
	if (args.targetLevel or 0) < config.minTargetLevel then
		return false, string.format("El objetivo debe ser nivel %d o superior.", config.minTargetLevel)
	end
	if (args.activeByPlacer or 0) >= config.maxActivePerPlacer then
		return false, string.format("Ya tienes %d recompensas activas.", config.maxActivePerPlacer)
	end
	if (args.placerCoins or 0) < amount then
		return false, "No tienes suficientes Tibia coins."
	end
	return true
end

-- attackers = { { id, accountId, ip, damage, lastHit, isPlayer }, ... }
-- target = { accountId, ip }; excludedAccounts = { [accountId] = true } (the bounty placers)
-- Returns the attackers that may share the reward, highest damage first.
function Core.eligibleKillers(attackers, target, excludedAccounts, now)
	local result = {}
	local seen = {}
	for _, a in ipairs(attackers) do
		local recent = now - (a.lastHit or 0) <= Core.config.recentHitMs
		local valid = a.isPlayer and recent and (a.damage or 0) > 0
			and a.accountId ~= target.accountId
			and not (excludedAccounts and excludedAccounts[a.accountId])
			and not (target.ip ~= 0 and a.ip == target.ip)
			and not seen[a.id]
		if valid then
			seen[a.id] = true
			result[#result + 1] = a
		end
	end
	table.sort(result, function(x, y)
		if x.damage == y.damage then
			return x.id < y.id
		end
		return x.damage > y.damage
	end)
	return result
end

-- Equal shares; the indivisible remainder goes to the highest damage dealers, one coin each.
-- killers must already be sorted by damage (eligibleKillers does it). Returns { [id] = coins }.
function Core.split(pot, killers)
	local shares = {}
	local count = #killers
	if count == 0 or pot <= 0 then
		return shares
	end
	local base = math.floor(pot / count)
	local remainder = pot - base * count
	for index, killer in ipairs(killers) do
		shares[killer.id] = base + (index <= remainder and 1 or 0)
	end
	return shares
end

-- Groups active bounty rows by target for the wanted list.
-- rows = { { targetId, targetName, level, vocation, pot, expiresAt }, ... }
-- Returns the top entries sorted by total reward: { targetId, name, level, vocation, reward, expiresAt (latest) }
function Core.wantedList(rows, now, limit)
	local byTarget, list = {}, {}
	for _, row in ipairs(rows) do
		if row.expiresAt > now then
			local entry = byTarget[row.targetId]
			if not entry then
				entry = { targetId = row.targetId, name = row.targetName, level = row.level, vocation = row.vocation, reward = 0, expiresAt = 0 }
				byTarget[row.targetId] = entry
				list[#list + 1] = entry
			end
			entry.reward = entry.reward + row.pot
			entry.expiresAt = math.max(entry.expiresAt, row.expiresAt)
		end
	end
	table.sort(list, function(a, b)
		if a.reward == b.reward then
			return a.expiresAt < b.expiresAt
		end
		return a.reward > b.reward
	end)
	limit = limit or Core.config.listSize
	while #list > limit do
		table.remove(list)
	end
	return list
end

-- Wire format sent with extended opcode: "L|name;reward;secondsLeft;level;vocation|..."
function Core.encodeList(list, now)
	local parts = { "L" }
	for _, entry in ipairs(list) do
		parts[#parts + 1] = string.format("%s;%d;%d;%d;%s", entry.name, entry.reward, math.max(0, entry.expiresAt - now), entry.level or 0, entry.vocation or "")
	end
	return table.concat(parts, "|")
end

function Core.decodeList(buffer)
	local list = {}
	if buffer:sub(1, 1) ~= "L" then
		return nil
	end
	for chunk in buffer:gmatch("|([^|]+)") do
		local name, reward, seconds, level, vocation = chunk:match("^([^;]+);(%d+);(%d+);(%d+);(.*)$")
		if name then
			list[#list + 1] = { name = name, reward = tonumber(reward), seconds = tonumber(seconds), level = tonumber(level), vocation = vocation }
		end
	end
	return list
end

function Core.formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%dm %02ds", minutes, seconds % 60)
end

return BountyCore
