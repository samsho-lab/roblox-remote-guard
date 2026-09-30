--!strict
--[[
	Janitor: collects things that need cleaning up and cleans them all at once.
	Same idea as Nevermore's Maid.

		local janitor = Janitor.new()
		janitor:add(part.Touched:Connect(onTouched))   -- :Disconnect()
		janitor:add(effect)                            -- :Destroy()
		janitor:add(function() print("cleaned") end)   -- called
		janitor:cleanup()

	Tasks are cleaned in reverse order of adding (last in, first out), so
	something added later that depends on an earlier object goes away first.
]]

type Task = any

export type Janitor = {
	add: <T>(self: Janitor, task: T, methodName: string?) -> T,
	cleanup: (self: Janitor) -> (),
	destroy: (self: Janitor) -> (),
	count: (self: Janitor) -> number,
}

type Self = {
	_tasks: { { task: Task, method: string? } },
	_cleaning: boolean,
}

local Janitor = {}
Janitor.__index = Janitor

function Janitor.new(): Janitor
	local self: Self = { _tasks = {}, _cleaning = false }
	return (setmetatable(self, Janitor) :: any) :: Janitor
end

local function methodFor(task: Task): string?
	local kind = typeof(task)
	if kind == "function" or kind == "thread" then
		return nil
	end
	if kind == "RBXScriptConnection" then
		return "Disconnect"
	end
	if kind == "Instance" then
		return "Destroy"
	end
	if kind == "table" then
		if type(task.Destroy) == "function" then
			return "Destroy"
		elseif type(task.Disconnect) == "function" then
			return "Disconnect"
		elseif type(task.destroy) == "function" then
			return "destroy"
		elseif type(task.disconnect) == "function" then
			return "disconnect"
		end
	end
	error("Janitor can't clean up a " .. kind .. " without a method name", 3)
end

function Janitor.add(self: Self, task: Task, methodName: string?): Task
	assert(task ~= nil, "Janitor:add() was given nil")
	local method = methodName or methodFor(task)
	table.insert(self._tasks, { task = task, method = method })
	return task
end

local function cancelThread(thread: thread)
	-- task.cancel only exists inside Roblox; coroutine.close works in plain Luau.
	local taskLib: any = task
	local cancel: ((thread) -> ())? = if taskLib ~= nil then taskLib.cancel else nil
	if cancel then
		cancel(thread)
	elseif coroutine.status(thread) ~= "running" then
		coroutine.close(thread)
	end
end

function Janitor.cleanup(self: Self)
	if self._cleaning then
		return
	end
	self._cleaning = true
	-- Loop instead of iterating a snapshot: if cleaning one task adds another
	-- (a destroy callback that registers more cleanup), that gets cleaned too.
	local tasks = self._tasks
	while #tasks > 0 do
		local entry = table.remove(tasks) :: { task: Task, method: string? }
		local t = entry.task
		if entry.method then
			(t :: any)[entry.method :: string](t)
		elseif type(t) == "function" then
			(t :: () -> ())()
		elseif type(t) == "thread" then
			cancelThread(t)
		end
	end
	self._cleaning = false
end

Janitor.destroy = Janitor.cleanup

function Janitor.count(self: Self): number
	return #self._tasks
end

return Janitor
