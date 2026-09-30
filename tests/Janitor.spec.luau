--!strict
local t = require("./harness")
local Janitor = require("../src/Janitor")

t.describe("Janitor", function()
	t.it("cleans functions, Destroy and Disconnect objects in reverse order", function()
		local order = {}
		local j = Janitor.new()
		j:add(function()
			table.insert(order, "fn")
		end)
		j:add({ Destroy = function()
			table.insert(order, "destroy")
		end })
		j:add({ Disconnect = function()
			table.insert(order, "disconnect")
		end })
		j:cleanup()
		t.expectEqual(table.concat(order, ","), "disconnect,destroy,fn")
		t.expectEqual(j:count(), 0)
	end)

	t.it("supports a custom method name", function()
		local closed = false
		local j = Janitor.new()
		j:add({ Close = function()
			closed = true
		end }, "Close")
		j:cleanup()
		t.expectTrue(closed)
	end)

	t.it("returns the added task for inline use", function()
		local j = Janitor.new()
		local obj = { Destroy = function() end }
		t.expectEqual(j:add(obj), obj)
	end)

	t.it("cleans tasks added during cleanup", function()
		local j = Janitor.new()
		local late = false
		j:add(function()
			j:add(function()
				late = true
			end)
		end)
		j:cleanup()
		-- The nested add happens while cleaning, so it's picked up by the same loop.
		t.expectTrue(late)
	end)

	t.it("closes suspended threads", function()
		local j = Janitor.new()
		local co = coroutine.create(function()
			coroutine.yield()
		end)
		coroutine.resume(co)
		j:add(co)
		j:cleanup()
		t.expectEqual(coroutine.status(co), "dead")
	end)

	t.it("errors on things it doesn't know how to clean", function()
		local j = Janitor.new()
		t.expectErrorContains(function()
			j:add({})
		end, "without a method name")
		t.expectErrorContains(function()
			j:add(nil :: any)
		end, "was given nil")
	end)

	t.it("is safe to call cleanup twice", function()
		local count = 0
		local j = Janitor.new()
		j:add(function()
			count += 1
		end)
		j:cleanup()
		j:destroy()
		t.expectEqual(count, 1)
	end)
end)

return {}
