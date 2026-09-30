# Remote Guard

![ci](https://github.com/samsho-lab/roblox-remote-guard/actions/workflows/ci.yml/badge.svg)

Small, typed Luau modules for keeping Roblox `RemoteEvent` handlers safe. Anything a client sends through a remote is untrusted, so this package gives you three things for every handler: check the arguments, rate-limit the sender, and clean up after yourself.

| Module | What it does |
|---|---|
| `Schema` | Validators for remote arguments: numbers (with NaN/inf rejection), strings, enums, arrays, strict objects, and whole argument lists |
| `RateLimiter` | Token-bucket rate limiting per player, with bursts and weighted costs |
| `Guard` | Wraps a handler so it only runs for calls that pass the limiter and the validator |
| `Janitor` | Maid-style cleanup of connections, instances, functions, and threads |

Everything is `--!strict`, has no dependencies, and is tested outside Roblox with the standalone `luau` CLI in CI.

## Example

```lua
local RemoteGuard = require(ReplicatedStorage.RemoteGuard)
local Schema, RateLimiter, Guard = RemoteGuard.Schema, RemoteGuard.RateLimiter, RemoteGuard.Guard

local limiter = RateLimiter.new({ rate = 3, burst = 5 }) -- 3/sec sustained, bursts of 5

Purchase.OnServerEvent:Connect(Guard.wrap({
	limiter = limiter,
	validate = Schema.args(
		Schema.oneOf("sword", "potion", "shield"),
		Schema.number({ integer = true, min = 1, max = 10 })
	),
	onReject = function(player, reason)
		warn(player.Name, reason) -- "rate_limited" or "invalid_args: argument 2: expected an integer, got 2.5"
	end,
}, function(player, itemId, quantity)
	-- Only reached with a known item and a whole number from 1 to 10.
end))

Players.PlayerRemoving:Connect(function(player)
	limiter:reset(player)
end)
```

A complete version is in [`examples/Shop.server.luau`](examples/Shop.server.luau).

## Why these checks matter

These are exploits that actually show up in Roblox games:

- **NaN and infinity.** `if quantity < 1 or quantity > 10 then return end` does *not* catch `0/0`, because every comparison with NaN is false. A client can send NaN and get through. `Schema.number()` rejects non-finite numbers unless you opt in.
- **Wrong types.** `Schema.string()` rejects a table sent where you expected a string, instead of letting it error halfway through your handler.
- **Extra arguments and keys.** `Schema.args` rejects calls with more arguments than expected, and `Schema.object` rejects unknown keys by default. Probing with junk fields gets bounced instead of silently accepted.
- **Remote spam.** An autoclicker or a loop firing a remote 1000 times a second is capped by the token bucket. Normal players double-clicking still get their burst.
- **Memory growth.** Rate-limiter state is per key, so it can leak if you never clear it. `reset(player)` on leave and `prune()` on a timer keep it bounded. `prune()` only removes buckets that have fully refilled, so it never changes behavior.

## API

### Schema

Each check is `(value) -> (boolean, string?)`. The string explains the failure, including the path: `argument 2: [3]: expected number, got string "x"`.

```lua
Schema.number({ min = 0, max = 100, integer = true, allowNonFinite = false })
Schema.string({ minLength = 1, maxLength = 32, pattern = "^%w+$" })
Schema.boolean()
Schema.typeof("Vector3")                       -- any typeof() name
Schema.oneOf("head", "chest", "legs")
Schema.optional(check)
Schema.array(check, { maxLength = 50 })        -- dense arrays only
Schema.object({ id = Schema.number() }, { strict = true })
Schema.args(check1, check2, ...)               -- validates a whole argument list
```

### RateLimiter

```lua
local limiter = RateLimiter.new({ rate = 5, burst = 10, clock = os.clock })
limiter:allow(player)        -- spends 1 token; returns false (and spends nothing) if empty
limiter:allow(player, 3)     -- weighted cost, e.g. for expensive actions
limiter:remaining(player)
limiter:reset(player)
limiter:prune()              -- drop fully refilled buckets; returns how many were removed
```

The clock is injectable, which is how the tests simulate time without waiting.

### Guard

```lua
Guard.wrap({ limiter = limiter?, validate = Schema.args(...)?, onReject = fn? }, handler)
```

The limiter runs before validation, so a client spamming garbage gets throttled without the server validating every call.

### Janitor

```lua
local janitor = Janitor.new()
janitor:add(connection)            -- :Disconnect()
janitor:add(instance)              -- :Destroy()
janitor:add(function() end)        -- called
janitor:add(thread)                -- task.cancel (coroutine.close outside Roblox)
janitor:add(obj, "Close")          -- custom method
janitor:cleanup()                  -- last in, first out
```

## Installing

**Wally:** the repo includes a `wally.toml`, so it can be published with `wally publish`. After that, a project would add:

```toml
[dependencies]
RemoteGuard = "samsho-lab/remote-guard@0.1.0"
```

**Rojo:** copy `src` into your project, or add this repo as a submodule and point a `$path` at `src`.

**Test place:** `rojo build dev.project.json -o RemoteGuardDev.rbxl` builds a place with the package in ReplicatedStorage and the example shop in ServerScriptService.

## Development

Tests run on the plain [Luau CLI](https://github.com/luau-lang/luau), so they don't need Roblox Studio:

```bash
luau tests/run.luau                    # 39 tests
luau-analyze src/Schema.luau src/RateLimiter.luau src/Guard.luau src/Janitor.luau tests
```

`src/init.luau` uses Roblox's `script`-based `require`, so it's left out of the CLI type check. CI runs the tests, the strict type check, and a Rojo build of both project files on every push.

## Layout

```
src/
  init.luau          package entry (Roblox)
  Schema.luau
  RateLimiter.luau
  Guard.luau
  Janitor.luau
tests/               harness + one spec per module
examples/            Shop.server.luau
default.project.json Rojo project for the package
dev.project.json     Rojo project for a test place
wally.toml
```
