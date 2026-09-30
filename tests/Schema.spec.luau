--!strict
local t = require("./harness")
local Schema = require("../src/Schema")

t.describe("Schema.number", function()
	local qty = Schema.number({ integer = true, min = 1, max = 99 })

	t.it("accepts values in range", function()
		t.expectTrue((qty(1)))
		t.expectTrue((qty(99)))
	end)

	t.it("rejects wrong types", function()
		local ok, err = qty("5")
		t.expectFalse(ok)
		t.expectTrue(string.find(err :: string, "expected number") ~= nil)
		t.expectFalse((qty({})))
		t.expectFalse((qty(nil)))
	end)

	t.it("rejects out-of-range and fractional values", function()
		t.expectFalse((qty(0)))
		t.expectFalse((qty(100)))
		t.expectFalse((qty(2.5)))
		t.expectFalse((qty(-1)))
	end)

	t.it("rejects NaN and infinity, which slip past naive range checks", function()
		local nan = 0 / 0
		t.expectFalse((Schema.number()(nan)))
		t.expectFalse((Schema.number()(math.huge)))
		t.expectFalse((Schema.number({ max = 10 })(-math.huge)))
		t.expectTrue((Schema.number({ allowNonFinite = true })(math.huge)))
	end)
end)

t.describe("Schema.string", function()
	local name = Schema.string({ minLength = 1, maxLength = 8, pattern = "^%w+$" })

	t.it("accepts valid strings", function()
		t.expectTrue((name("Sword01")))
	end)

	t.it("enforces length and pattern", function()
		t.expectFalse((name("")))
		t.expectFalse((name("waytoolongname")))
		t.expectFalse((name("bad name")))
		t.expectFalse((name(12)))
	end)
end)

t.describe("Schema.oneOf / boolean / typeof / optional", function()
	t.it("oneOf matches only listed literals", function()
		local slot = Schema.oneOf("head", "chest", "legs")
		t.expectTrue((slot("head")))
		t.expectFalse((slot("feet")))
	end)

	t.it("boolean", function()
		t.expectTrue((Schema.boolean()(false)))
		t.expectFalse((Schema.boolean()(0)))
	end)

	t.it("typeof checks Luau type names", function()
		t.expectTrue((Schema.typeof("table")({})))
		t.expectFalse((Schema.typeof("Vector3")({})))
	end)

	t.it("optional allows nil only", function()
		local maybe = Schema.optional(Schema.number())
		t.expectTrue((maybe(nil)))
		t.expectTrue((maybe(3)))
		t.expectFalse((maybe("3")))
	end)
end)

t.describe("Schema.array", function()
	local ids = Schema.array(Schema.number({ integer = true }), { maxLength = 3 })

	t.it("accepts dense arrays", function()
		t.expectTrue((ids({ 1, 2, 3 })))
		t.expectTrue((ids({})))
	end)

	t.it("rejects bad elements with the index in the message", function()
		local ok, err = ids({ 1, "x" })
		t.expectFalse(ok)
		t.expectTrue(string.find(err :: string, "[2]", 1, true) ~= nil)
	end)

	t.it("rejects dictionaries, holes, and oversize arrays", function()
		t.expectFalse((ids({ a = 1 })))
		t.expectFalse((ids({ [1] = 1, [3] = 3 })))
		t.expectFalse((ids({ 1, 2, 3, 4 })))
	end)
end)

t.describe("Schema.object", function()
	local order = Schema.object({
		item = Schema.string({ maxLength = 32 }),
		quantity = Schema.number({ integer = true, min = 1 }),
		gift = Schema.optional(Schema.boolean()),
	})

	t.it("accepts a valid shape", function()
		t.expectTrue((order({ item = "sword", quantity = 2 })))
		t.expectTrue((order({ item = "sword", quantity = 2, gift = true })))
	end)

	t.it("reports the failing field", function()
		local ok, err = order({ item = "sword", quantity = 0 })
		t.expectFalse(ok)
		t.expectTrue(string.find(err :: string, "quantity:", 1, true) ~= nil)
	end)

	t.it("rejects unknown keys by default", function()
		t.expectFalse((order({ item = "sword", quantity = 1, price = 0 })))
	end)

	t.it("can allow unknown keys", function()
		local loose = Schema.object({ id = Schema.number() }, { strict = false })
		t.expectTrue((loose({ id = 1, extra = true })))
	end)
end)

t.describe("Schema.args", function()
	local check = Schema.args(Schema.string(), Schema.optional(Schema.number()))

	t.it("validates each argument", function()
		t.expectTrue((check("a", 1)))
		t.expectTrue((check("a")))
		local ok, err = check(1)
		t.expectFalse(ok)
		t.expectTrue(string.find(err :: string, "argument 1", 1, true) ~= nil)
	end)

	t.it("rejects extra arguments", function()
		t.expectFalse((check("a", 1, "extra")))
	end)

	t.it("counts trailing nils as arguments", function()
		t.expectFalse((check("a", 1, nil)))
	end)
end)

return {}
