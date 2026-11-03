-- Battle Royale ranked mode: pure rules (no game API), so they can be unit tested outside the server.
-- See tests/lua/test_battle_royale_core.lua. The game integration lives in data/scripts/systems/battle_royale.lua.
BattleRoyaleCore = {}
local Core = BattleRoyaleCore

Core.config = {
	minPlayers = 2, -- a match can start with this many players
	minRankedPlayers = 4, -- fewer players than this: the match does not change ratings
	maxPlayers = 30,
	minLevel = 100, -- level in the normal game required to queue
	lobbyCountdown = 60, -- seconds between reaching minPlayers and the start
	graceTime = 20, -- seconds without damage after spawning
	matchLevel = 200, -- every participant plays at this level
	startRating = 1000,
	ratingFloor = 0,
	kFactor = 32,
	killBonus = 4, -- rating points per kill, added after the placement change
	maxKillBonus = 20,
	idleWarning = 90, -- seconds without dealing or taking damage
	idleLimit = 120, -- eliminated after this many idle seconds
	minMatchesForReward = 5,
	-- Safe zone (square, Chebyshev distance from the centre) shrinks in phases
	arenaRadius = 25,
	phases = {
		{ wait = 60, shrink = 30, radius = 18, damage = 0.03 },
		{ wait = 45, shrink = 30, radius = 11, damage = 0.05 },
		{ wait = 40, shrink = 25, radius = 6, damage = 0.08 },
		{ wait = 30, shrink = 20, radius = 2, damage = 0.12 },
		{ wait = 20, shrink = 15, radius = 0, damage = 0.20 },
	},
}

-- Leagues, lowest first. A league starts at its rating.
Core.leagues = {
	{ id = "bronze", name = "Bronce", rating = 0 },
	{ id = "silver", name = "Plata", rating = 1100 },
	{ id = "gold", name = "Oro", rating = 1300 },
	{ id = "platinum", name = "Platino", rating = 1500 },
	{ id = "diamond", name = "Diamante", rating = 1700 },
}

-- Equalized combat stats per base vocation (1 sorcerer, 2 druid, 3 paladin, 4 knight, 9 monk).
-- Skill ids follow SKILL_FIST=0 .. SKILL_FISHING=6.
Core.vocationStats = {
	[1] = { magic = 85, skills = { [0] = 10, [1] = 10, [2] = 10, [3] = 10, [4] = 10, [5] = 25 } },
	[2] = { magic = 85, skills = { [0] = 10, [1] = 10, [2] = 10, [3] = 10, [4] = 10, [5] = 25 } },
	[3] = { magic = 25, skills = { [0] = 10, [1] = 10, [2] = 10, [3] = 10, [4] = 105, [5] = 90 } },
	[4] = { magic = 10, skills = { [0] = 10, [1] = 100, [2] = 100, [3] = 100, [4] = 10, [5] = 95 } },
	[9] = { magic = 30, skills = { [0] = 100, [1] = 10, [2] = 10, [3] = 10, [4] = 10, [5] = 85 } },
}

function Core.leagueFor(rating)
	local current = Core.leagues[1]
	for _, league in ipairs(Core.leagues) do
		if rating >= league.rating then
			current = league
		end
	end
	return current
end

-- Max health/mana at a level, with the same formula Canary uses from level 8 (185 hp / 90 mana base)
function Core.statsForLevel(level, healthGain, manaGain)
	local levels = math.max(0, level - 8)
	return 185 + levels * healthGain, 90 + levels * manaGain
end

function Core.combatStats(baseVocationId)
	return Core.vocationStats[baseVocationId] or Core.vocationStats[4]
end

-- Safe zone radius after `elapsed` seconds of the running phase. Returns radius, phase index, damage ratio.
function Core.zoneAt(elapsed, config)
	config = config or Core.config
	local radius = config.arenaRadius
	local time = 0
	local damage = config.phases[1].damage
	for index, phase in ipairs(config.phases) do
		damage = phase.damage
		if elapsed < time + phase.wait then
			return radius, index, damage, false
		end
		time = time + phase.wait
		if elapsed < time + phase.shrink then
			local progress = (elapsed - time) / phase.shrink
			local value = radius - (radius - phase.radius) * progress
			return math.floor(value + 0.5), index, damage, true
		end
		time = time + phase.shrink
		radius = phase.radius
	end
	return radius, #config.phases, damage, false
end

function Core.isOutsideZone(position, center, radius)
	return math.max(math.abs(position.x - center.x), math.abs(position.y - center.y)) > radius
end

-- Expected score of a against b (standard Elo)
function Core.expected(ratingA, ratingB)
	return 1 / (1 + 10 ^ ((ratingB - ratingA) / 400))
end

-- Multiplayer Elo: every pair of participants counts as a duel won by the better placement.
-- participants = { { id = ..., rating = ..., placement = 1 (winner) .. n, kills = ... }, ... }
-- Returns { [id] = delta } with deltas rounded to integers.
function Core.ratingChanges(participants, config)
	config = config or Core.config
	local count = #participants
	local changes = {}
	if count < 2 then
		for _, p in ipairs(participants) do
			changes[p.id] = 0
		end
		return changes
	end

	for _, p in ipairs(participants) do
		local actual, expected = 0, 0
		for _, other in ipairs(participants) do
			if other ~= p then
				expected = expected + Core.expected(p.rating, other.rating)
				if p.placement < other.placement then
					actual = actual + 1
				elseif p.placement == other.placement then
					actual = actual + 0.5
				end
			end
		end
		local delta = config.kFactor * (actual - expected) / (count - 1) * math.min(count - 1, 4)
		local bonus = math.min((p.kills or 0) * config.killBonus, config.maxKillBonus)
		delta = delta + bonus
		local rounded = delta >= 0 and math.floor(delta + 0.5) or -math.floor(-delta + 0.5)
		if p.rating + rounded < config.ratingFloor then
			rounded = config.ratingFloor - p.rating
		end
		changes[p.id] = rounded
	end
	return changes
end

-- Placement points for the scoreboard (not the rating)
function Core.matchScore(placement, count, kills, survivedSeconds)
	local placementPoints = math.max(0, count - placement) * 10
	if placement == 1 then
		placementPoints = placementPoints + 50
	end
	return placementPoints + (kills or 0) * 15 + math.floor((survivedSeconds or 0) / 30)
end

-- Weighted loot roll. tiers = { { weight = n, items = { { name, count }, ... } }, ... }
-- rng(n) must return an integer in [1, n] (math.random by default).
function Core.rollLoot(tiers, rng)
	rng = rng or math.random
	local total = 0
	for _, tier in ipairs(tiers) do
		total = total + tier.weight
	end
	if total <= 0 then
		return nil
	end
	local pick = rng(total)
	for _, tier in ipairs(tiers) do
		pick = pick - tier.weight
		if pick <= 0 then
			if #tier.items == 0 then
				return nil
			end
			return tier.items[rng(#tier.items)], tier
		end
	end
	return nil
end

-- Season key from a unix time (one season per calendar month), e.g. 202611
function Core.seasonKey(timestamp)
	local date = os.date("*t", timestamp)
	return date.year * 100 + date.month
end

-- Returns true when the IP is free in the given queue/match ({ [playerId] = ip })
function Core.ipAllowed(entries, ip)
	if ip == 0 then
		return true
	end
	for _, entryIp in pairs(entries) do
		if entryIp == ip then
			return false
		end
	end
	return true
end

return BattleRoyaleCore
