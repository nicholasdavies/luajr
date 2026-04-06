-----------------
-- 8. DEBUGGER --
-----------------

-- Debugger module
local dbg = nil
local dbg_queue = {}
local dbg_xmsg = "~!#DBGEXIT#!~"

-- Custom dbg.read function
-- Allows running commands "invisibly" from a queue.
local function dbg_read(prompt)
    if #dbg_queue > 0 then
        return table.remove(dbg_queue)
    end
    return luajr.readline(prompt)
end

-- Custom dbg.write function
-- Allows 'q' to trigger a graceful exit.
-- Allows running commands "invisibly" from a queue.
local function dbg_write(str)
    if string.find(str, dbg_xmsg, 1, true) then
        error(dbg_xmsg)
    end
    if #dbg_queue == 0 then
        io.write(str)
    end
end

-- Custom dbg.exit function
-- Allows 'q' to trigger a graceful exit.
local function dbg_exit()
    error(dbg_xmsg)
end

-- Ensure debugger.lua is loaded
local function check_dbg()
    if dbg == nil then
        local errmsg
        dbg, errmsg = loadfile(debugger_lua_path)
        if dbg == nil then error(errmsg) end
        dbg = dbg() -- loadfile returns a function of the file's contents
        dbg.read = dbg_read
        dbg.write = dbg_write
        dbg.exit = dbg_exit
        dbg.auto_where = 1
    end
end

-- Debugger message handler access
function luajr.dbg_msgh()
    check_dbg()
    return dbg.msgh
end

-- Debugger access
function luajr.dbg(...)
    check_dbg()
    return dbg(...)
end

-- Trigger debugger for stepping into a call
function luajr.dbg_step_into(...)
    check_dbg()
    dbg_queue = { "s", "n" }
    return dbg(...)
end


