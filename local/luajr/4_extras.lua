--------------------
-- 6. EXTRA TYPES --
--------------------

-- Attribute set/getters
sexp_get_attr = function(s, k)
    local a = R.getAttrib(s, R.install(k))
    local t = R.TYPEOF(a)
    if t == R.NILSXP then return nil end
    if t == R.LGLSXP then
        return luajr.logical(a, byref)
    elseif t == R.INTSXP then
        return luajr.integer(a, byref)
    elseif t == R.REALSXP then
        return luajr.numeric(a, byref)
    elseif t == R.STRSXP then
        return luajr.character(a, byref)
    else
        error("Cannot get attribute of type " .. R.type_string(a))
    end
end

sexp_set_attr = function(s, k, v)
    if k == "/matrix/colnames" and luajr.is_character(v) then
        local dimnames = R.allocVector(R.VECSXP, 2)
        R.PROTECT(dimnames)
        R.SET_VECTOR_ELT(dimnames, 0, R.NilValue)
        R.SET_VECTOR_ELT(dimnames, 1, v.s)
        R.dimnamesgets(s, dimnames)
        R.UNPROTECT(1)
    elseif luajr.is_logical(v) or luajr.is_integer(v) or
           luajr.is_numeric(v) or luajr.is_character(v) then
        R.setAttrib(s, R.install(k), v.s)
    else
        error("No attribute setter for type " .. type(v) .. ".")
    end
end

-- Does obj have indexing and length capabilities?
vectorish = function(obj)
    return type(obj) == "table" or luajr.is_logical(obj) or luajr.is_integer(obj) or
        luajr.is_numeric(obj) or luajr.is_character(obj)
end

-- dataframe type
function luajr.dataframe()
    local df = luajr.list()
    df[0].class = "data.frame"

    return df
end

-- matrix reference type: specify nrow and ncol
function luajr.matrix_r(nrow, ncol)
    local m = luajr.numeric(nrow * ncol, 0.0)

    -- Make dimensions
    local dim = luajr.integer(2)
    dim[1] = nrow
    dim[2] = ncol
    m:attr("dim", dim)

    return m
end

-- datamatrix reference type: specify nrow, ncol, and column names
function luajr.datamatrix_r(nrow, ncol, names)
    local m = luajr.matrix_r(nrow, ncol)

    -- Make column names
    if #names > ncol then error("Supplied more names than columns to luajr.datamatrix_r.") end
    local colnames = luajr.character(ncol)
    for i = 1,#names do colnames[i] = names[i] end
    m:attr("/matrix/colnames", colnames)

    return m
end



-----------------
-- 7. DEBUGGER --
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


