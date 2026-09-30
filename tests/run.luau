--!strict
-- Runs every spec. Usage (from the repo root): luau tests/run.luau
local harness = require("./harness")

require("./Schema.spec")
require("./RateLimiter.spec")
require("./Guard.spec")
require("./Janitor.spec")

local failed = harness.summary()
if failed > 0 then
	error(string.format("%d test(s) failed", failed), 0)
end
