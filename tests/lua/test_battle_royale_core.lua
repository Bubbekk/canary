-- Standalone Lua tests for the Battle Royale rules.
-- Run from the repository root with: luajit tests/lua/test_battle_royale_core.lua

local passed, failed, errors = 0, 0, {}

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		table.insert(errors, { name = name, err = err })
	end
end

local function assert_true(value, message)
	if not value then
		error(message or "expected true", 2)
	end
end

local function assert_equal(expected, actual, message)
	if expected ~= actual then
		error(message or string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

local Core = dofile("data/libs/systems/battle_royale_core.lua")
local config = Core.config

test("leagues follow their rating thresholds", function()
	assert_equal("bronze", Core.leagueFor(0).id)
	assert_equal("bronze", Core.leagueFor(1099).id)
	assert_equal("silver", Core.leagueFor(1100).id)
	assert_equal("gold", Core.leagueFor(1300).id)
	assert_equal("platinum", Core.leagueFor(1500).id)
	assert_equal("diamond", Core.leagueFor(1700).id)
	assert_equal("diamond", Core.leagueFor(5000).id)
	assert_equal("bronze", Core.leagueFor(config.startRating).id, "new players start in bronze")
end)

test("level stats use the level 8 base", function()
	local hp, mana = Core.statsForLevel(8, 15, 5)
	assert_equal(185, hp)
	assert_equal(90, mana)
	hp, mana = Core.statsForLevel(200, 15, 5) -- knight gains
	assert_equal(185 + 192 * 15, hp)
	assert_equal(90 + 192 * 5, mana)
	hp = Core.statsForLevel(1, 15, 5)
	assert_equal(185, hp, "below level 8 never goes under the base")
end)

test("combat stats exist for every base vocation and fall back to knight", function()
	for _, vocation in ipairs({ 1, 2, 3, 4, 9 }) do
		local stats = Core.combatStats(vocation)
		assert_true(stats.magic > 0 and stats.skills[5] > 0, "vocation " .. vocation)
	end
	assert_equal(Core.vocationStats[4], Core.combatStats(0))
	assert_equal(Core.vocationStats[4], Core.combatStats(42))
end)

test("safe zone waits, shrinks linearly and ends at the last radius", function()
	local r, phase, damage, shrinking = Core.zoneAt(0)
	assert_equal(config.arenaRadius, r)
	assert_equal(1, phase)
	assert_equal(false, shrinking)
	assert_equal(config.phases[1].damage, damage)

	local first = config.phases[1]
	r, phase, damage, shrinking = Core.zoneAt(first.wait + first.shrink / 2)
	assert_true(shrinking)
	local mid = math.floor(config.arenaRadius - (config.arenaRadius - first.radius) / 2 + 0.5)
	assert_equal(mid, r)

	r = Core.zoneAt(first.wait + first.shrink)
	assert_equal(first.radius, r)

	local total = 0
	for _, p in ipairs(config.phases) do
		total = total + p.wait + p.shrink
	end
	r, phase, damage = Core.zoneAt(total + 1000)
	assert_equal(config.phases[#config.phases].radius, r)
	assert_equal(#config.phases, phase)
	assert_equal(config.phases[#config.phases].damage, damage)
end)

test("safe zone radius never grows over time", function()
	local last = math.huge
	for t = 0, 1000 do
		local r = Core.zoneAt(t)
		assert_true(r <= last, "radius grew at t=" .. t)
		last = r
	end
end)

test("zone damage gets stronger every phase", function()
	for index = 2, #config.phases do
		assert_true(config.phases[index].damage > config.phases[index - 1].damage)
		assert_true(config.phases[index].radius < config.phases[index - 1].radius)
	end
end)

test("outside check uses the square (Chebyshev) distance", function()
	local c = { x = 100, y = 100 }
	assert_equal(false, Core.isOutsideZone({ x = 105, y = 95 }, c, 5))
	assert_equal(true, Core.isOutsideZone({ x = 106, y = 100 }, c, 5))
	assert_equal(true, Core.isOutsideZone({ x = 100, y = 94 }, c, 5))
	assert_equal(false, Core.isOutsideZone({ x = 100, y = 100 }, c, 0))
	assert_equal(true, Core.isOutsideZone({ x = 101, y = 100 }, c, 0))
end)

test("elo expectation is symmetric", function()
	local a = Core.expected(1200, 1000)
	local b = Core.expected(1000, 1200)
	assert_true(math.abs(a + b - 1) < 1e-9)
	assert_true(a > 0.5)
	assert_true(math.abs(Core.expected(1000, 1000) - 0.5) < 1e-9)
end)

test("equal ratings: winner gains, last loses, middle is neutral", function()
	local changes = Core.ratingChanges({
		{ id = 1, rating = 1000, placement = 1, kills = 0 },
		{ id = 2, rating = 1000, placement = 2, kills = 0 },
		{ id = 3, rating = 1000, placement = 3, kills = 0 },
	})
	assert_true(changes[1] > 0)
	assert_equal(0, changes[2])
	assert_true(changes[3] < 0)
	assert_equal(-changes[1], changes[3], "without kills the changes balance out")
end)

test("beating a stronger field is worth more than beating a weaker one", function()
	local vsStrong = Core.ratingChanges({
		{ id = 1, rating = 1000, placement = 1, kills = 0 },
		{ id = 2, rating = 1500, placement = 2, kills = 0 },
	})
	local vsWeak = Core.ratingChanges({
		{ id = 1, rating = 1000, placement = 1, kills = 0 },
		{ id = 2, rating = 500, placement = 2, kills = 0 },
	})
	assert_true(vsStrong[1] > vsWeak[1])
end)

test("kill bonus is added and capped", function()
	local base = Core.ratingChanges({
		{ id = 1, rating = 1000, placement = 1, kills = 0 },
		{ id = 2, rating = 1000, placement = 2, kills = 0 },
	})
	local withKills = Core.ratingChanges({
		{ id = 1, rating = 1000, placement = 1, kills = 2 },
		{ id = 2, rating = 1000, placement = 2, kills = 0 },
	})
	assert_equal(base[1] + 2 * config.killBonus, withKills[1])
	local capped = Core.ratingChanges({
		{ id = 1, rating = 1000, placement = 1, kills = 100 },
		{ id = 2, rating = 1000, placement = 2, kills = 0 },
	})
	assert_equal(base[1] + config.maxKillBonus, capped[1])
end)

test("rating never drops below the floor", function()
	local changes = Core.ratingChanges({
		{ id = 1, rating = 10, placement = 1, kills = 0 },
		{ id = 2, rating = 10, placement = 2, kills = 0 },
	})
	assert_true(10 + changes[2] == config.ratingFloor, "a loss at 10 rating is clamped to the floor")
	assert_true(changes[1] > 0)
end)

test("a lone participant does not change rating", function()
	local changes = Core.ratingChanges({ { id = 7, rating = 1000, placement = 1, kills = 3 } })
	assert_equal(0, changes[7])
end)

test("large lobbies keep changes bounded", function()
	local participants = {}
	for i = 1, 30 do
		participants[i] = { id = i, rating = 1000, placement = i, kills = 0 }
	end
	local changes = Core.ratingChanges(participants)
	for i = 1, 30 do
		assert_true(math.abs(changes[i]) <= config.kFactor * 4, "change too large for " .. i)
	end
	assert_true(changes[1] > changes[15] and changes[15] > changes[30])
end)

test("match score rewards placement, kills and survival", function()
	assert_equal(9 * 10 + 50, Core.matchScore(1, 10, 0, 0))
	assert_equal(0, Core.matchScore(10, 10, 0, 0))
	assert_equal(15 * 2 + 4, Core.matchScore(10, 10, 2, 120))
	assert_true(Core.matchScore(1, 10, 0, 0) > Core.matchScore(2, 10, 0, 0))
end)

test("loot roll respects tier weights", function()
	local tiers = {
		{ weight = 3, items = { { "a", 1 } } },
		{ weight = 1, items = { { "b", 1 }, { "c", 2 } } },
	}
	local item, tier = Core.rollLoot(tiers, function(n)
		return n == 4 and 3 or 1
	end)
	assert_equal("a", item[1])
	assert_equal(tiers[1], tier)
	item = Core.rollLoot(tiers, function(n)
		return n == 4 and 4 or 2
	end)
	assert_equal("c", item[1])
	assert_equal(2, item[2])

	local counts = { a = 0, b = 0, c = 0 }
	math.randomseed(42)
	for _ = 1, 4000 do
		local rolled = Core.rollLoot(tiers)
		counts[rolled[1]] = counts[rolled[1]] + 1
	end
	assert_true(counts.a > 2700 and counts.a < 3300, "common tier around 75%")
end)

test("loot roll handles empty tables", function()
	assert_equal(nil, Core.rollLoot({}))
	assert_equal(nil, Core.rollLoot({ { weight = 1, items = {} } }, function()
		return 1
	end))
end)

test("season key is year and month", function()
	local t = os.time({ year = 2026, month = 11, day = 3, hour = 12 })
	assert_equal(202611, Core.seasonKey(t))
	assert_equal(202612, Core.seasonKey(os.time({ year = 2026, month = 12, day = 31, hour = 12 })))
end)

test("ip check blocks duplicates but not unknown addresses", function()
	local entries = { [1] = 100, [2] = 200 }
	assert_equal(false, Core.ipAllowed(entries, 100))
	assert_equal(true, Core.ipAllowed(entries, 300))
	assert_equal(true, Core.ipAllowed(entries, 0))
end)

test("config is internally consistent", function()
	assert_true(config.minPlayers >= 2)
	assert_true(config.minRankedPlayers >= config.minPlayers)
	assert_true(config.maxPlayers >= config.minRankedPlayers)
	assert_true(config.idleLimit > config.idleWarning)
	assert_true(config.phases[1].radius < config.arenaRadius)
	assert_true(config.phases[#config.phases].radius >= 0)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if #errors > 0 then
	print("\nFailed tests:")
	for _, entry in ipairs(errors) do
		print(string.format("  FAIL: %s\n        %s", entry.name, entry.err))
	end
	os.exit(1)
end
