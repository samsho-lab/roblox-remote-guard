--!strict
-- Example: a shop purchase remote that can't be spammed or fed bad data.
-- Build a test place with: rojo build dev.project.json -o RemoteGuardDev.rbxl
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteGuard = require(ReplicatedStorage.RemoteGuard)
local Schema = RemoteGuard.Schema
local RateLimiter = RemoteGuard.RateLimiter
local Guard = RemoteGuard.Guard
local Janitor = RemoteGuard.Janitor

local PRICES = { sword = 150, potion = 25, shield = 120 }

local purchase = Instance.new("RemoteEvent")
purchase.Name = "Purchase"
purchase.Parent = ReplicatedStorage

-- 3 purchases per second sustained, bursts of up to 5.
local limiter = RateLimiter.new({ rate = 3, burst = 5 })

local validatePurchase = Schema.args(
	Schema.oneOf("sword", "potion", "shield"),
	Schema.number({ integer = true, min = 1, max = 10 })
)

local janitor = Janitor.new()

janitor:add(purchase.OnServerEvent:Connect(Guard.wrap({
	limiter = limiter,
	validate = validatePurchase,
	onReject = function(player: Player, reason: string)
		warn(string.format("[Purchase] rejected %s: %s", player.Name, reason))
	end,
}, function(player: Player, itemId: string, quantity: number)
	-- Everything here has already been checked. The price comes from the
	-- server table, never from the client.
	local cost = PRICES[itemId] * quantity
	print(string.format("%s buys %d x %s for %d", player.Name, quantity, itemId, cost))
end)))

janitor:add(Players.PlayerRemoving:Connect(function(player)
	limiter:reset(player)
end))

-- Prune idle buckets once a minute so the limiter never grows unbounded.
janitor:add(task.spawn(function()
	while true do
		task.wait(60)
		limiter:prune()
	end
end))

script.Destroying:Connect(function()
	janitor:cleanup()
end)
