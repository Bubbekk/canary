-- Standalone Lua tests for the bounty (sicariato) rules.
-- Run from the repository root with: luajit tests/lua/test_bounty_core.lua

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

local Core = dofile("data/libs/systems/bounty_core.lua")
local config = Core.config

local function placement(overrides)
	local args = { amount = 100, hours = 24, placerCoins = 1000, placerAccount = 1, targetAccount = 2, targetLevel = 100, targetIsStaff = false, activeByPlacer = 0 }
	for key, value in pairs(overrides or {}) do
		args[key] = value
	end
	return args
end

test("a normal placement is accepted", function()
	assert_equal(true, Core.validatePlacement(placement()))
end)

test("amount limits and integers", function()
	assert_equal(false, (Core.validatePlacement(placement({ amount = config.minReward - 1 }))))
	assert_equal(true, (Core.validatePlacement(placement({ amount = config.minReward }))))
	assert_equal(true, (Core.validatePlacement(placement({ amount = config.maxReward, placerCoins = config.maxReward }))))
	assert_equal(false, (Core.validatePlacement(placement({ amount = config.maxReward + 1, placerCoins = 10 ^ 9 }))))
	assert_equal(false, (Core.validatePlacement(placement({ amount = 100.5 }))))
	assert_equal(false, (Core.validatePlacement(placement({ amount = "100" }))))
end)

test("only configured durations are allowed", function()
	for _, hours in ipairs(config.durations) do
		assert_equal(true, (Core.validatePlacement(placement({ hours = hours }))))
	end
	assert_equal(false, (Core.validatePlacement(placement({ hours = 0 }))))
	assert_equal(false, (Core.validatePlacement(placement({ hours = 1000 }))))
end)

test("target rules: exists, not staff, not own account, minimum level", function()
	local missing = placement()
	missing.targetAccount = nil
	local ok, reason = Core.validatePlacement(missing)
	assert_equal(false, ok)
	assert_true(reason:find("no existe"))
	assert_equal(false, (Core.validatePlacement(placement({ targetIsStaff = true }))))
	assert_equal(false, (Core.validatePlacement(placement({ targetAccount = 1 }))), "own account is rejected")
	assert_equal(false, (Core.validatePlacement(placement({ targetLevel = config.minTargetLevel - 1 }))))
	assert_equal(true, (Core.validatePlacement(placement({ targetLevel = config.minTargetLevel }))))
end)

test("placer needs the coins and a free slot", function()
	assert_equal(false, (Core.validatePlacement(placement({ placerCoins = 99 }))))
	assert_equal(true, (Core.validatePlacement(placement({ placerCoins = 100 }))))
	assert_equal(false, (Core.validatePlacement(placement({ activeByPlacer = config.maxActivePerPlacer }))))
end)

test("fee is a floor percentage and the pot is the rest", function()
	local fee, pot = Core.fee(100)
	assert_equal(10, fee)
	assert_equal(90, pot)
	fee, pot = Core.fee(55)
	assert_equal(5, fee)
	assert_equal(50, pot)
	fee, pot = Core.fee(config.minReward)
	assert_equal(config.minReward, fee + pot)
end)

local NOW = 1000000

local function attacker(id, accountId, damage, overrides)
	local a = { id = id, accountId = accountId, ip = 1000 + id, damage = damage, lastHit = NOW - 1000, isPlayer = true }
	for key, value in pairs(overrides or {}) do
		a[key] = value
	end
	return a
end

test("eligible killers: recent player hits only, sorted by damage", function()
	local list = Core.eligibleKillers({
		attacker(1, 11, 100),
		attacker(2, 12, 500),
		attacker(3, 13, 300, { lastHit = NOW - config.recentHitMs - 1 }), -- too old
		attacker(4, 14, 0), -- no damage
		attacker(5, 15, 50, { isPlayer = false }), -- monster
	}, { accountId = 99, ip = 9 }, {}, NOW)
	assert_equal(2, #list)
	assert_equal(2, list[1].id)
	assert_equal(1, list[2].id)
end)

test("eligible killers exclude the target's account, its IP and the placers", function()
	local list = Core.eligibleKillers({
		attacker(1, 99, 100), -- same account as the target
		attacker(2, 12, 100, { ip = 9 }), -- same connection as the target
		attacker(3, 50, 100), -- placed the bounty
		attacker(4, 14, 100),
	}, { accountId = 99, ip = 9 }, { [50] = true }, NOW)
	assert_equal(1, #list)
	assert_equal(4, list[1].id)
end)

test("eligible killers ignore duplicated attackers", function()
	local list = Core.eligibleKillers({ attacker(1, 11, 100), attacker(1, 11, 100) }, { accountId = 99, ip = 9 }, {}, NOW)
	assert_equal(1, #list)
end)

test("an unknown target ip (0) does not exclude everyone", function()
	local list = Core.eligibleKillers({ attacker(1, 11, 100, { ip = 0 }) }, { accountId = 99, ip = 0 }, {}, NOW)
	assert_equal(1, #list)
end)

test("split is equal and gives the remainder to top damage", function()
	local killers = { { id = 1 }, { id = 2 }, { id = 3 } }
	local shares = Core.split(100, killers)
	assert_equal(34, shares[1])
	assert_equal(33, shares[2])
	assert_equal(33, shares[3])
	assert_equal(100, shares[1] + shares[2] + shares[3], "no coin is lost or created")
end)

test("split never loses coins for any pot and group size", function()
	for pot = 0, 300, 7 do
		for count = 1, 12 do
			local killers = {}
			for i = 1, count do
				killers[i] = { id = i }
			end
			local shares = Core.split(pot, killers)
			local total = 0
			for _, value in pairs(shares) do
				total = total + value
				assert_true(value >= math.floor(pot / count))
			end
			assert_equal(pot, total, string.format("pot %d count %d", pot, count))
		end
	end
	assert_equal(nil, next(Core.split(100, {})))
end)

test("wanted list groups bounties per target and sorts by reward", function()
	local list = Core.wantedList({
		{ targetId = 1, targetName = "Alice", level = 100, vocation = "Knight", pot = 90, expiresAt = NOW + 100 },
		{ targetId = 2, targetName = "Bob", level = 200, vocation = "Druid", pot = 200, expiresAt = NOW + 50 },
		{ targetId = 1, targetName = "Alice", level = 100, vocation = "Knight", pot = 180, expiresAt = NOW + 500 },
		{ targetId = 3, targetName = "Old", level = 80, vocation = "", pot = 9999, expiresAt = NOW - 1 }, -- expired
	}, NOW)
	assert_equal(2, #list)
	assert_equal("Alice", list[1].name)
	assert_equal(270, list[1].reward)
	assert_equal(NOW + 500, list[1].expiresAt, "time shown is the latest expiry")
	assert_equal("Bob", list[2].name)
end)

test("wanted list respects the size limit", function()
	local rows = {}
	for i = 1, 25 do
		rows[i] = { targetId = i, targetName = "P" .. i, level = 60, vocation = "", pot = i, expiresAt = NOW + 10 }
	end
	local list = Core.wantedList(rows, NOW)
	assert_equal(config.listSize, #list)
	assert_equal(25, list[1].reward)
	assert_equal(3, #Core.wantedList(rows, NOW, 3))
end)

test("list encoding round-trips", function()
	local list = {
		{ name = "Sir Gaw", reward = 270, expiresAt = NOW + 3600, level = 100, vocation = "Elite Knight" },
		{ name = "Bob", reward = 50, expiresAt = NOW - 5, level = 60, vocation = "" },
	}
	local encoded = Core.encodeList(list, NOW)
	assert_equal("L|Sir Gaw;270;3600;100;Elite Knight|Bob;50;0;60;", encoded)
	local decoded = Core.decodeList(encoded)
	assert_equal(2, #decoded)
	assert_equal("Sir Gaw", decoded[1].name)
	assert_equal(270, decoded[1].reward)
	assert_equal(3600, decoded[1].seconds)
	assert_equal("Elite Knight", decoded[1].vocation)
	assert_equal(0, decoded[2].seconds)
	assert_equal(0, #Core.decodeList("L"))
	assert_equal(nil, Core.decodeList("M|hola"))
end)

test("time formatting", function()
	assert_equal("2h 05m", Core.formatTime(2 * 3600 + 5 * 60 + 30))
	assert_equal("4m 09s", Core.formatTime(249))
	assert_equal("0m 00s", Core.formatTime(-10))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if #errors > 0 then
	print("\nFailed tests:")
	for _, entry in ipairs(errors) do
		print(string.format("  FAIL: %s\n        %s", entry.name, entry.err))
	end
	os.exit(1)
end
