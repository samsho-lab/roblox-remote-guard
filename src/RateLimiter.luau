--!strict
--[[
	RateLimiter: token bucket, one bucket per key (usually a Player or UserId).

	Each key starts with `burst` tokens and regains `rate` tokens per second,
	up to `burst`. Every allowed call spends tokens. This allows a short burst
	(double-clicking a button) while capping the sustained rate (an autoclicker
	or a remote-spam script).

		local limiter = RateLimiter.new({ rate = 5, burst = 10 })
		if not limiter:allow(player) then return end
]]

export type Options = {
	rate: number, -- tokens regained per second
	burst: number, -- bucket size
	clock: (() -> number)?, -- injectable for tests; defaults to os.clock
}

type Bucket = { tokens: number, updated: number }

export type RateLimiter = {
	allow: (self: RateLimiter, key: any, cost: number?) -> boolean,
	remaining: (self: RateLimiter, key: any) -> number,
	reset: (self: RateLimiter, key: any) -> (),
	prune: (self: RateLimiter) -> number,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Self = {
	_rate: number,
	_burst: number,
	_clock: () -> number,
	_buckets: { [any]: Bucket },
}

function RateLimiter.new(options: Options): RateLimiter
	assert(options.rate > 0, "rate must be positive")
	assert(options.burst >= 1, "burst must be at least 1")
	local self: Self = {
		_rate = options.rate,
		_burst = options.burst,
		_clock = options.clock or os.clock,
		_buckets = {},
	}
	return (setmetatable(self, RateLimiter) :: any) :: RateLimiter
end

local function refill(self: Self, key: any): Bucket
	local now = self._clock()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._burst, updated = now }
		self._buckets[key] = bucket
		return bucket
	end
	local elapsed = math.max(0, now - bucket.updated)
	bucket.tokens = math.min(self._burst, bucket.tokens + elapsed * self._rate)
	bucket.updated = now
	return bucket
end

-- Spends `cost` tokens (default 1) if available. Returns false without
-- spending anything if the key is over its limit.
function RateLimiter.allow(self: Self, key: any, cost: number?): boolean
	local amount = cost or 1
	local bucket = refill(self, key)
	if bucket.tokens >= amount then
		bucket.tokens -= amount
		return true
	end
	return false
end

function RateLimiter.remaining(self: Self, key: any): number
	return refill(self, key).tokens
end

-- Forget a key, e.g. on Players.PlayerRemoving, so the table doesn't grow forever.
function RateLimiter.reset(self: Self, key: any)
	self._buckets[key] = nil
end

-- Drop every bucket that has refilled completely. A full bucket behaves the
-- same as no bucket, so this frees memory without changing behavior.
-- Returns how many buckets were removed.
function RateLimiter.prune(self: Self): number
	local now = self._clock()
	local removed = 0
	for key, bucket in self._buckets do
		local tokens = bucket.tokens + math.max(0, now - bucket.updated) * self._rate
		if tokens >= self._burst then
			self._buckets[key] = nil
			removed += 1
		end
	end
	return removed
end

return RateLimiter
