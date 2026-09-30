--!strict
-- A very small test harness so the suite runs with the plain `luau` CLI,
-- outside Roblox Studio.

local harness = {}

local results = { passed = 0, failed = 0 }
local currentSuite = ""

function harness.describe(name: string, body: () -> ())
	currentSuite = name
	body()
end

function harness.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	if ok then
		results.passed += 1
		print("  ok    " .. currentSuite .. " > " .. name)
	else
		results.failed += 1
		print("  FAIL  " .. currentSuite .. " > " .. name .. "\n        " .. tostring(err))
	end
end

function harness.expectEqual(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", if label then label .. ": " else "", tostring(expected), tostring(actual)), 2)
	end
end

function harness.expectTrue(value: any, label: string?)
	if value ~= true then
		error((label or "expected true") .. ", got " .. tostring(value), 2)
	end
end

function harness.expectFalse(value: any, label: string?)
	if value ~= false then
		error((label or "expected false") .. ", got " .. tostring(value), 2)
	end
end

function harness.expectErrorContains(fn: () -> (), fragment: string)
	local ok, err = pcall(fn)
	if ok then
		error("expected an error containing '" .. fragment .. "'", 2)
	end
	if not string.find(tostring(err), fragment, 1, true) then
		error("error '" .. tostring(err) .. "' does not contain '" .. fragment .. "'", 2)
	end
end

function harness.summary(): number
	print(string.format("\n%d passed, %d failed", results.passed, results.failed))
	return results.failed
end

return harness
