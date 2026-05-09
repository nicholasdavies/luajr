--------------------
-- 4. EXTRA TYPES --
--------------------

-- Convert SEXP to luajr type by TYPEOF dispatch
from_sexp = function(s, mode)
    mode = mode or alias
    local t = R.TYPEOF(s)
    if     t == R.NILSXP  then return R.NilValue
    elseif t == R.LGLSXP  then return luajr.logical(s, mode)
    elseif t == R.INTSXP  then return luajr.integer(s, mode)
    elseif t == R.REALSXP then return luajr.numeric(s, mode)
    elseif t == R.STRSXP  then return luajr.character(s, mode)
    elseif t == R.VECSXP  then return luajr.list(s, mode)
    elseif t == R.CLOSXP or t == R.SPECIALSXP or t == R.BUILTINSXP then
        return luajr.rfunction(s)
    elseif t == R.ENVSXP  then return luajr.environment(s)
    else return s
    end
end
luajr.from_sexp = from_sexp

-- Convert luajr type or Lua scalar to SEXP
to_sexp = function(v)
    if v == nil then return R.NilValue end
    local t = type(v)
    if t == "cdata" then
        if luajr.is_logical(v) or luajr.is_integer(v) or
           luajr.is_numeric(v) or luajr.is_character(v) or
           luajr.is_list(v) then
            return v.s
        elseif ffi.istype(R.sexp, v) then
            return v
        elseif ffi.istype(luajr.rfunction, v) then
            return v.s
        elseif ffi.istype(luajr.environment, v) then
            return v.s
        else
            error("cannot convert cdata of this type to SEXP", 2)
        end
    elseif t == "boolean" then return R.ScalarLogical(v)
    elseif t == "number" then return R.ScalarReal(v)
    elseif t == "string" then return R.ScalarString(R.mkChar(v))
    else
        error("cannot convert " .. t .. " to SEXP", 2)
    end
end
luajr.to_sexp = to_sexp

-- Does obj have indexing and length capabilities?
vectorish = function(obj)
    return type(obj) == "table" or luajr.is_logical(obj) or luajr.is_integer(obj) or
        luajr.is_numeric(obj) or luajr.is_character(obj) or luajr.is_list(obj)
end

-- dataframe type
function luajr.dataframe()
    local df = luajr.list()
    df:set_attr("class", "data.frame")
    return df
end

-- matrix type: specify nrow and ncol
function luajr.matrix(nrow, ncol)
    local m = luajr.numeric(nrow * ncol, 0.0)

    -- Make dimensions
    local dim = luajr.integer(2)
    dim[1] = nrow
    dim[2] = ncol
    m:set_attr("dim", dim)

    return m
end

-- datamatrix type: specify nrow, ncol, and column names
function luajr.datamatrix(nrow, ncol, names)
    local m = luajr.matrix(nrow, ncol)

    -- Make column names via dimnames list
    if #names > ncol then error("Supplied more names than columns to luajr.datamatrix.", 2) end
    local colnames = luajr.character(ncol)
    for i = 1,#names do colnames[i] = names[i] end
    local dimnames = luajr.list()
    dimnames:push_back(R.NilValue)
    dimnames:push_back(colnames)
    R.dimnamesgets(m.s, dimnames.s)

    return m
end

-- environment type
-- typedef struct { SEXP s; } environment_t;
local methods_environment = {
    get = function(self, k)
        local val = R.get_var(k, self.s)
        if val then return from_sexp(val) end
    end,

    set = function(self, k, v)
        R.defineVar(R.install(k), to_sexp(v), self.s)
    end,

    exists = function(self, k)
        return R.get_var(k, self.s) ~= nil
    end,

    remove = function(self, k)
        R.removeVarFromFrame(R.install(k), self.s)
    end,

    get_parent = function(self)
        return luajr.environment(R.ParentEnv(self.s))
    end,

    set_parent = function(self, env)
        if ffi.istype(luajr.environment, env) then
            R.set_parent(self.s, env.s)
        elseif ffi.istype(R.sexp, env) and R.TYPEOF(env) == R.ENVSXP then
            R.set_parent(self.s, env)
        else
            error("Cannot set parent to object of type " .. type(env), 2)
        end
    end,

    ls = function(self, all)
        return luajr.character(R.lsInternal(self.s, all and 1 or 0))
    end
}

local mt_environment = {
    __new = function(ctype, a)
        local self = ffi.new(ctype)
        if a == nil then
            self.s = R.new_env()
        elseif ffi.istype(R.sexp, a) and R.TYPEOF(a) == R.ENVSXP then
            self.s = a
        elseif type(a) == "string" then
            self.s = R.get_namespace(a)
        else
            error("cannot construct R environment from type " .. type(a), 2)
        end
        R.PreserveObject(self.s)
        return self
    end,

    __gc = function(self)
        R.ReleaseObject(self.s)
    end,

    __index = function(self, k)
        return methods_environment[k]
    end,

    __newindex = function(self, k, v)
        error("use :get(k) and :set(k, v) to access environment.", 2)
    end
}

luajr.environment = ffi.metatype("environment_t", mt_environment)

-- R function type
-- typedef struct { SEXP s; SEXP cached; } function_t;
local mt_rfunction = {
    __new = function(ctype, a, b)
        local self = ffi.new(ctype)
        if ffi.istype(R.sexp, a) then
            local typ = R.TYPEOF(a)
            if typ == R.CLOSXP or typ == R.SPECIALSXP or typ == R.BUILTINSXP then
                self.s = a
            else
                error("cannot construct R function from SXPTYPE " .. R.type_string(a) .. ".", 2)
            end
        elseif type(a) == "string" then
            local env = luajr.environment(b or R.GlobalEnv)
            self.s = R.findFun(R.install(a), env.s)
        else
            error("cannot construct R function with argument types " .. type(a) ..
                ", " ..type(b) .. ".", 2)
        end
        R.PreserveObject(self.s)
        self.cached = R.NilValue
        return self
    end,

    __gc = function(self)
        R.ReleaseObject(self.s)
    end,

    __call = function(self, ...)
        return luajr.Rcall(self.s, ...)
    end
}

luajr.rfunction = ffi.metatype("function_t", mt_rfunction)

luajr.is_environment = function(obj) return ffi.istype(luajr.environment, obj) end
luajr.is_rfunction   = function(obj) return ffi.istype(luajr.rfunction, obj) end



-----------------
-- 5. PARALLEL --
-----------------

-- Query number of cores
luajr.ncores = function()
    return internal.luajr_parallel_ncores()
end

-- Workers type
-- typedef struct { lua_State** l; int n; } workers_t;
local methods_workers = {
    preload = function(self, f, ...)
        luajr.parallel_load(self, f, ...)
    end,

    srun = function(self, f, ...)
        if f ~= nil then self:preload(f, ...) end
        internal.luajr_parallel_srun(get_thisstate(), self)
    end,

    prun = function(self, f, ...)
        if f ~= nil then self:preload(f, ...) end
        internal.luajr_parallel_prun(get_thisstate(), self)
    end,

    pfor = function(self, i0, i1, f, ...)
        if f ~= nil then self:preload(f, ...) end
        internal.luajr_parallel_pfor(get_thisstate(), self, i0, i1)
    end,

    close = function(self)
        if self.l ~= nullptr then
            internal.luajr_parallel_closeworkers(self)
        end
    end
}

local mt_workers = {
    __new = function(ctype, n)
        local self = ffi.new(ctype)
        if n == nil then
            self.n = luajr.ncores()
        elseif type(n) == "number" and n >= 1 then
            self.n = n
        else
            error("worker number must be a positive integer or nil", 2)
        end
        internal.luajr_parallel_newworkers(get_thisstate(), self)
        return self
    end,

    __gc = function(self)
        self:close()
    end,

    __index = function(self, k)
        return methods_workers[k]
    end,

    __len = function(self)
        return self.n
    end
}

luajr.workers = ffi.metatype("workers_t", mt_workers)



-----------------
-- 6. DEBUGGER --
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


