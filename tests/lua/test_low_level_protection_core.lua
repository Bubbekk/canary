-- Standalone Lua tests for the low level protection rule.
-- Run from the repository root with: luajit tests/lua/test_low_level_protection_core.lua

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

local function assert_equal(expected, actual, message)
	if expected ~= actual then
		error(message or string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

local Core = dofile("data/libs/systems/low_level_protection_core.lua")
local Bounty = dofile("data/libs/systems/bounty_core.lua")

test("protects a lethal hit up to the max level, inclusive", function()
	assert_equal(true, Core.shouldProtect(1, 100, 100, false, false))
	assert_equal(true, Core.shouldProtect(Core.maxLevel, 100, 500, false, false))
	assert_equal(false, Core.shouldProtect(Core.maxLevel + 1, 100, 500, false, false))
end)

test("non lethal hits pass through", function()
	assert_equal(false, Core.shouldProtect(20, 100, 99, false, false))
	assert_equal(true, Core.shouldProtect(20, 100, 100, false, false), "exactly the remaining health is lethal")
end)

test("healing and Battle Royale players are never intercepted", function()
	assert_equal(false, Core.shouldProtect(20, 10, 1000, true, false))
	assert_equal(false, Core.shouldProtect(20, 10, 1000, false, true))
end)

test("bounties can only target players that can actually die", function()
	assert_equal(Core.maxLevel + 1, Bounty.config.minTargetLevel)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if #errors > 0 then
	print("\nFailed tests:")
	for _, entry in ipairs(errors) do
		print(string.format("  FAIL: %s\n        %s", entry.name, entry.err))
	end
	os.exit(1)
end
