local skynet = require "skynet"
local snax = require "snax"

local cmd = {}
local service = {}

local GLOBAL = false

local function request(name, func, ...)
	local ok, handle = pcall(func, ...)
	local s = service[name]
	assert(type(s) == "table")
	if ok then
		service[name] = handle
	else
		service[name] = tostring(handle)
	end

	for _,v in ipairs(s) do
		skynet.wakeup(v)
	end

	if ok then
		return handle
	else
		error(tostring(handle))
	end
end

local function waitfor(name , func, ...)
	local s = service[name]
	if type(s) == "number" then
		return s
	end
	local co = coroutine.running()

	if s == nil then
		s = {}
		service[name] = s
	elseif type(s) == "string" then
		error(s)
	end

	assert(type(s) == "table")

	if not s.launch and func then
		s.launch = true
		return request(name, func, ...)
	end

	table.insert(s, co)
	skynet.wait()
	s = service[name]
	if type(s) == "string" then
		error(s)
	end
	assert(type(s) == "number")
	return s
end

function cmd.LAUNCH(service_name, subname, ...)
	if service_name == "snaxd" then
		return waitfor("snax."..subname, snax.rawnewservice, subname, ...)
	else
		return waitfor(service_name, skynet.newservice, service_name, subname, ...)
	end
end

function cmd.QUERY(service_name, subname)
	if service_name == "snaxd" then
		return waitfor("snax."..subname)
	else
		return waitfor(service_name)
	end
end

function cmd.GLAUNCH(...)
	if GLOBAL then
		return cmd.LAUNCH(...)
	else
		return waitfor(service_name, skynet.call, "SERVICE", "lua", "LAUNCH", ...)
	end
end

function cmd.GQUERY(...)
	if GLOBAL then
		return cmd.QUERY(...)
	else
		return waitfor(service_name, skynet.call, "SERVICE", "lua", "QUERY", ...)
	end
end

skynet.start(function()
	skynet.dispatch("lua", function(session, address, command, ...)
		local f = cmd[command]
		if f == nil then
			skynet.ret(skynet.pack(nil, "Invalid command " .. command))
			return
		end

		local ok, r = pcall(f, ...)

		if ok then
			skynet.ret(skynet.pack(r))
		else
			skynet.ret(skynet.pack(nil, r))
		end
	end)
	skynet.register(".service")
	if skynet.getenv "standalone" then
		GLOBAL = true
		skynet.register("SERVICE")
	end
end)
