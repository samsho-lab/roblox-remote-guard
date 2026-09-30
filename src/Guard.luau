--!strict
--[[
	Guard: wraps a RemoteEvent handler so it only runs for calls that pass a
	rate limit and argument validation.

		Remote.OnServerEvent:Connect(Guard.wrap({
			limiter = RateLimiter.new({ rate = 4, burst = 8 }),
			validate = Schema.args(Schema.string({ maxLength = 32 }), Schema.number({ integer = true, min = 1 })),
			onReject = function(player, reason) warn(player.Name, reason) end,
		}, function(player, itemId, quantity)
			-- only reached with valid arguments
		end))

	The rate limit is checked before validation, so a client spamming garbage
	gets throttled without the server spending time validating every call.
]]

export type Options = {
	validate: ((...any) -> (boolean, string?))?,
	-- Anything with an :allow(key) method, normally a RateLimiter.
	limiter: any?,
	-- Called with (player, reason) for every rejected call. Reasons start with
	-- "rate_limited" or "invalid_args" so they're easy to count in analytics.
	onReject: ((player: any, reason: string) -> ())?,
}

local Guard = {}

function Guard.wrap(options: Options, handler: (player: any, ...any) -> ()): (player: any, ...any) -> ()
	local validate = options.validate
	local limiter = options.limiter
	local onReject = options.onReject

	return function(player: any, ...: any)
		if limiter and not limiter:allow(player) then
			if onReject then
				onReject(player, "rate_limited")
			end
			return
		end
		if validate then
			local ok, err = validate(...)
			if not ok then
				if onReject then
					onReject(player, "invalid_args: " .. (err or "unknown"))
				end
				return
			end
		end
		handler(player, ...)
	end
end

return Guard
