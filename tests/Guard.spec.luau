--!strict
local t = require("./harness")
local Guard = require("../src/Guard")
local Schema = require("../src/Schema")
local RateLimiter = require("../src/RateLimiter")

t.describe("Guard.wrap", function()
	local function setup()
		local now = 0
		local calls = {}
		local rejects = {}
		local handler = Guard.wrap({
			limiter = RateLimiter.new({ rate = 1, burst = 2, clock = function()
				return now
			end }),
			validate = Schema.args(Schema.string({ maxLength = 10 }), Schema.number({ integer = true, min = 1 })),
			onReject = function(player, reason)
				table.insert(rejects, { player = player, reason = reason })
			end,
		}, function(player, item, qty)
			table.insert(calls, { player = player, item = item, qty = qty })
		end)
		return handler, calls, rejects
	end

	t.it("passes valid calls through with the original arguments", function()
		local handler, calls = setup()
		local player = { Name = "ava" }
		handler(player, "sword", 2)
		t.expectEqual(#calls, 1)
		t.expectEqual(calls[1].player, player)
		t.expectEqual(calls[1].item, "sword")
		t.expectEqual(calls[1].qty, 2)
	end)

	t.it("blocks invalid arguments and reports why", function()
		local handler, calls, rejects = setup()
		handler({}, "sword", -5)
		handler({}, { exploit = true }, 1)
		t.expectEqual(#calls, 0)
		t.expectEqual(#rejects, 2)
		t.expectTrue(string.find(rejects[1].reason, "invalid_args", 1, true) ~= nil)
	end)

	t.it("rate limits per player before validating", function()
		local handler, calls, rejects = setup()
		local spammer, other = {}, {}
		handler(spammer, "a", 1)
		handler(spammer, "a", 1)
		handler(spammer, "a", 1)
		handler(other, "a", 1)
		t.expectEqual(#calls, 3)
		t.expectEqual(#rejects, 1)
		t.expectEqual(rejects[1].player, spammer)
		t.expectEqual(rejects[1].reason, "rate_limited")
	end)

	t.it("works with no limiter or validator", function()
		local count = 0
		local handler = Guard.wrap({}, function()
			count += 1
		end)
		handler({}, "anything")
		t.expectEqual(count, 1)
	end)
end)

return {}
