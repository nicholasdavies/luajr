--------------------
-- 4. EXTRA TYPES --
--------------------

-- Does obj have indexing and length capabilities?
vectorish = function(obj)
    return type(obj) == "table" or luajr.is_logical(obj) or luajr.is_integer(obj) or
        luajr.is_numeric(obj) or luajr.is_character(obj) or luajr.is_list(obj)
end

-- dataframe type
local df_classname = R.ScalarString(R.mkChar("data.frame"))
R.PreserveObject(df_classname)
function luajr.dataframe(a, b)
    local df = luajr.list(a, b)
    R.classgets(df.s, df_classname)
    return df
end

-- matrix type: specify nrow, ncol, and init
function luajr.matrix(nrow, ncol, init)
    local m = luajr.numeric(nrow * ncol, init)

    -- Make dimensions
    local dim = luajr.integer(2)
    dim[1] = nrow
    dim[2] = ncol
    R.dimgets(m.s, dim.s)

    return m
end

-- datamatrix type: specify nrow, ncol, column names, and init
function luajr.datamatrix(nrow, ncol, names, init)
    local m = luajr.matrix(nrow, ncol, init)

    -- Make column names via dimnames list
    if #names > ncol then error("Supplied more names than columns to luajr.datamatrix.", 2) end
    local dimnames = luajr.list(2)
    dimnames[2] = luajr.character(names)
    R.dimnamesgets(m.s, dimnames.s)

    return m
end

-- environment type
-- typedef struct { SEXP s; } environment_t;
local methods_environment = {
    get = function(self, k)
        local val = R.getVarEx(R.install(k), self.s, 0, R.UnboundValue)
        if val ~= R.UnboundValue then return from_sexp(val) else return nil end
    end,

    set = function(self, k, v)
        R.defineVar(R.install(k), to_sexp(v), self.s)
    end,

    exists = function(self, k)
        return self:get(k) ~= nil
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

    ls = function(self, all, sorted)
        if all == nil then all = false end
        if sorted == nil then sorted = true end
        return luajr.character(R.lsInternal3(self.s, all and 1 or 0, sorted and 1 or 0))
    end
}

local mt_environment = {
    __new = function(ctype, a)
        local self = ffi.new(ctype)
        if a == nil then
            self.s = R.NewEnv(R.EmptyEnv, 1, 29)
        elseif ffi.istype(R.sexp, a) and R.TYPEOF(a) == R.ENVSXP then
            self.s = a
        elseif type(a) == "string" then
            self.s = R.getRegisteredNamespace(a)
            if self.s == R.NilValue then
                error("could not find namespace " .. a, 2)
            end
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
luajr.is_environment = function(obj) return ffi.istype(luajr.environment, obj) end

-- R function type
-- typedef struct { SEXP s; SEXP cached; } function_t;
local methods_rfunction = {
    -- in args table, integer keys are positional 1..#args,
    -- string keys are named, env defaults to GlobalEnv if nil
    call = function(self, args, env)
        return luajr.rcall(self.s, args, env)
    end
}

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

    __index = function(self, k)
        return methods_rfunction[k]
    end,

    __call = function(self, ...)
        return luajr.rcall(self.s, {...})
    end
}

luajr.rfunction = ffi.metatype("function_t", mt_rfunction)
luajr.is_rfunction = function(obj) return ffi.istype(luajr.rfunction, obj) end



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
        internal.luajr_parallel_srun(this_state, self)
    end,

    prun = function(self, f, ...)
        if f ~= nil then self:preload(f, ...) end
        internal.luajr_parallel_prun(this_state, self)
    end,

    pfor = function(self, i0, i1, f, ...)
        if f ~= nil then self:preload(f, ...) end
        internal.luajr_parallel_pfor(this_state, self, i0, i1)
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
        internal.luajr_parallel_newworkers(this_state, self)
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


