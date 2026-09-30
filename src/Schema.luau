--!strict
--[[
	Schema: small combinators for validating data that arrives from the client.

	Anything a client sends through a RemoteEvent is untrusted. An exploiter
	can send any value: a table where you expected a number, NaN, a 10 MB
	string, a negative quantity. Each check here is a function that returns
	`true`, or `false` plus a readable reason.

		local check = Schema.args(
			Schema.string({ maxLength = 32 }),       -- item id
			Schema.number({ integer = true, min = 1, max = 99 }), -- quantity
		)
		local ok, err = check("sword", 3)
]]

export type Check = (value: any) -> (boolean, string?)

local Schema = {}

local function describe(value: any): string
	local kind = typeof(value)
	if kind == "string" then
		local s = value :: string
		if #s > 20 then
			s = string.sub(s, 1, 20) .. "..."
		end
		return string.format("string %q", s)
	elseif kind == "number" or kind == "boolean" then
		return kind .. " " .. tostring(value)
	end
	return kind
end

export type NumberOptions = {
	min: number?,
	max: number?,
	integer: boolean?,
	-- NaN and +/-inf are rejected unless this is true. NaN in particular breaks
	-- comparisons (NaN < x and NaN > x are both false), so it slips past most
	-- range checks.
	allowNonFinite: boolean?,
}

function Schema.number(options: NumberOptions?): Check
	local opts: NumberOptions = options or {}
	return function(value)
		if type(value) ~= "number" then
			return false, "expected number, got " .. describe(value)
		end
		if not opts.allowNonFinite and (value ~= value or value == math.huge or value == -math.huge) then
			return false, "expected a finite number, got " .. tostring(value)
		end
		if opts.integer and value % 1 ~= 0 then
			return false, "expected an integer, got " .. tostring(value)
		end
		if opts.min ~= nil and value < opts.min then
			return false, string.format("expected >= %s, got %s", tostring(opts.min), tostring(value))
		end
		if opts.max ~= nil and value > opts.max then
			return false, string.format("expected <= %s, got %s", tostring(opts.max), tostring(value))
		end
		return true, nil
	end
end

export type StringOptions = {
	minLength: number?,
	maxLength: number?,
	pattern: string?,
}

function Schema.string(options: StringOptions?): Check
	local opts: StringOptions = options or {}
	return function(value)
		if type(value) ~= "string" then
			return false, "expected string, got " .. describe(value)
		end
		local len = #value
		if opts.minLength and len < opts.minLength then
			return false, string.format("expected at least %d characters, got %d", opts.minLength, len)
		end
		if opts.maxLength and len > opts.maxLength then
			return false, string.format("expected at most %d characters, got %d", opts.maxLength, len)
		end
		if opts.pattern and not string.find(value, opts.pattern) then
			return false, "string does not match pattern " .. opts.pattern
		end
		return true, nil
	end
end

function Schema.boolean(): Check
	return function(value)
		if type(value) ~= "boolean" then
			return false, "expected boolean, got " .. describe(value)
		end
		return true, nil
	end
end

-- Matches any Luau/Roblox type name from typeof(), e.g. "Vector3" or "Instance".
function Schema.typeof(typeName: string): Check
	return function(value)
		if typeof(value) ~= typeName then
			return false, "expected " .. typeName .. ", got " .. describe(value)
		end
		return true, nil
	end
end

-- Value must be exactly one of the given literals.
function Schema.oneOf(...: any): Check
	local allowed = table.pack(...)
	return function(value)
		for i = 1, allowed.n do
			if allowed[i] == value then
				return true, nil
			end
		end
		return false, "value " .. describe(value) .. " is not one of the allowed options"
	end
end

function Schema.optional(check: Check): Check
	return function(value)
		if value == nil then
			return true, nil
		end
		return check(value)
	end
end

export type ArrayOptions = {
	maxLength: number?,
}

-- A dense array (keys 1..n, nothing else) where every element passes `check`.
function Schema.array(check: Check, options: ArrayOptions?): Check
	local opts: ArrayOptions = options or {}
	return function(value)
		if type(value) ~= "table" then
			return false, "expected array, got " .. describe(value)
		end
		local count = 0
		for key in value do
			count += 1
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
				return false, "expected array, found key " .. describe(key)
			end
		end
		if count ~= #value then
			return false, "expected array without holes"
		end
		if opts.maxLength and count > opts.maxLength then
			return false, string.format("expected at most %d elements, got %d", opts.maxLength, count)
		end
		for i, element in ipairs(value) do
			local ok, err = check(element)
			if not ok then
				return false, string.format("[%d]: %s", i, err or "invalid")
			end
		end
		return true, nil
	end
end

export type ObjectOptions = {
	-- Reject keys that are not in the shape. On by default: extra keys from
	-- a client are almost always a bug or an exploit probe.
	strict: boolean?,
}

function Schema.object(shape: { [string]: Check }, options: ObjectOptions?): Check
	local strict = if options and options.strict == false then false else true
	return function(value)
		if type(value) ~= "table" then
			return false, "expected table, got " .. describe(value)
		end
		if strict then
			for key in value do
				if type(key) ~= "string" or shape[key] == nil then
					return false, "unexpected key " .. describe(key)
				end
			end
		end
		for key, check in shape do
			local ok, err = check(value[key])
			if not ok then
				return false, key .. ": " .. (err or "invalid")
			end
		end
		return true, nil
	end
end

--[[
	Validates a whole argument list, as received by OnServerEvent (after the
	player argument). Extra arguments are rejected, so a client can't pad a
	call with junk that the handler never looks at.
]]
function Schema.args(...: Check): (...any) -> (boolean, string?)
	local checks = { ... }
	return function(...)
		local n = select("#", ...)
		if n > #checks then
			return false, string.format("expected at most %d arguments, got %d", #checks, n)
		end
		for i, check in checks do
			local ok, err = check((select(i, ...)))
			if not ok then
				return false, string.format("argument %d: %s", i, err or "invalid")
			end
		end
		return true, nil
	end
end

return Schema
