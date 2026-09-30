--!strict
local t = require("./harness")
local RateLimiter = require("../src/RateLimiter")

local function fakeClock()
	local now = 0
	return function()
		return now
	end, function(seconds: number)
		now += seconds
	end
end

t.describe("RateLimiter", function()
	t.it("allows a burst, then blocks", function()
		local clock = fakeClock()
		local limiter = RateLimiter.new({ rate = 1, burst = 3, clock = clock })
		t.expectTrue(limiter:allow("p1"))
		t.expectTrue(limiter:allow("p1"))
		t.expectTrue(limiter:allow("p1"))
		t.expectFalse(limiter:allow("p1"))
	end)

	t.it("refills over time at the configured rate", function()
		local clock, advance = fakeClock()
		local limiter = RateLimiter.new({ rate = 2, burst = 2, clock = clock })
		limiter:allow("p1")
		limiter:allow("p1")
		t.expectFalse(limiter:allow("p1"))
		advance(0.5) -- 0.5 s * 2/s = 1 token
		t.expectTrue(limiter:allow("p1"))
		t.expectFalse(limiter:allow("p1"))
	end)

	t.it("never refills past the burst size", function()
		local clock, advance = fakeClock()
		local limiter = RateLimiter.new({ rate = 10, burst = 3, clock = clock })
		advance(1000)
		t.expectEqual(limiter:remaining("p1"), 3)
	end)

	t.it("tracks keys independently", function()
		local clock = fakeClock()
		local limiter = RateLimiter.new({ rate = 1, burst = 1, clock = clock })
		t.expectTrue(limiter:allow("a"))
		t.expectFalse(limiter:allow("a"))
		t.expectTrue(limiter:allow("b"))
	end)

	t.it("supports weighted costs and does not spend on failure", function()
		local clock = fakeClock()
		local limiter = RateLimiter.new({ rate = 1, burst = 5, clock = clock })
		t.expectTrue(limiter:allow("p", 4))
		t.expectFalse(limiter:allow("p", 2))
		t.expectEqual(limiter:remaining("p"), 1)
	end)

	t.it("sustained spam is capped at the refill rate", function()
		local clock, advance = fakeClock()
		local limiter = RateLimiter.new({ rate = 5, burst = 5, clock = clock })
		local allowed = 0
		for _ = 1, 600 do -- 600 attempts over 10 seconds (60 per second)
			if limiter:allow("spammer") then
				allowed += 1
			end
			advance(1 / 60)
		end
		-- 5 from the initial burst + about 5/s * 10 s refill
		t.expectTrue(allowed <= 56, "allowed " .. allowed)
		t.expectTrue(allowed >= 50, "allowed " .. allowed)
	end)

	t.it("reset and prune free memory", function()
		local clock, advance = fakeClock()
		local limiter = RateLimiter.new({ rate = 1, burst = 2, clock = clock })
		limiter:allow("a")
		limiter:allow("b")
		limiter:allow("b")
		limiter:reset("a")
		t.expectEqual(limiter:remaining("a"), 2)
		advance(0.5)
		t.expectEqual(limiter:prune(), 1) -- "a" is full again, "b" is not
		advance(5)
		t.expectEqual(limiter:prune(), 1)
	end)

	t.it("validates options", function()
		t.expectErrorContains(function()
			RateLimiter.new({ rate = 0, burst = 1 })
		end, "rate must be positive")
	end)
end)

return {}
