-- luajr module

-- CONTENTS --
-- 0. PRELIMINARIES --
-- 1. INTERNAL API --
-- 2. LUAJR API BASICS --
-- 3. VECTOR TYPES --
-- 4. EXTRA TYPES --
-- 5. PARALLEL --
-- 6. DEBUGGER --



----------------------
-- 0. PRELIMINARIES --
----------------------

-- Load ffi module
local ffi = require("ffi")

-- Load additional convenience functions for tables (provided by LuaJIT)
table.new = require("table.new")
table.clear = require("table.clear")

-- Load R module
local R = require("R")

-- Script receives the path to the luajr R package dylib as argument
local luajr_dylib_path = ({...})[1]

-- Script also receives the path to debugger.lua as argument
local debugger_lua_path = ({...})[2]

-- Null pointer object
local nullptr = ffi.cast("void*", 0)

-- Pointer-to-pointer type for writing pointer values
local voidpp = ffi.typeof("void**")

-- Pointer-to-sexp type for writing SEXP values
local sexpp  = ffi.typeof("SEXP*")

-- "Hidden" sentinel object (unused)
ffi.cdef[[ typedef struct { int a; } HIDDEN_t; ]]
local hidden = ffi.new("HIDDEN_t")



---------------------
-- 1. INTERNAL API --
---------------------

-- 'Internal' API for interfacing with C, R; struct types
ffi.cdef[[
// Forward declarations
struct SEXPREC;
struct lua_State;
typedef struct lua_State lua_State;
typedef struct SEXPREC* SEXP;

// R vector types
typedef struct { int* p;    SEXP s; double n; double c; } logical_t;
typedef struct { int* p;    SEXP s; double n; double c; } integer_t;
typedef struct { double* p; SEXP s; double n; double c; } numeric_t;
typedef struct { SEXP* p;   SEXP s; double n; double c; } character_t;
typedef struct { SEXP* p;   SEXP s; double n; double c; } list_t;

// Other R types
typedef struct { SEXP s; } environment_t;
typedef struct { SEXP s; SEXP cached; } function_t;

// Other luajr types
typedef struct { lua_State** l; int n; } workers_t;

// C functions
void* memcpy(void* dest, const void* src, size_t count);
size_t strlen(const char* str);

// Parallel functionality
int luajr_parallel_ncores();
void luajr_parallel_newworkers(lua_State* L, workers_t* w);
void luajr_parallel_closeworkers(workers_t* w);
void luajr_parallel_srun(lua_State* L, workers_t* w);
void luajr_parallel_prun(lua_State* L, workers_t* w);
void luajr_parallel_pfor(lua_State* L, workers_t* w, int i0, int i1);
]]
local internal = ffi.load(luajr_dylib_path)

-- Cache the current lua_State* for FFI calls that need pcall-aware error handling.
-- luajr.thisstate is registered as a lua_CFunction in state.cpp, after this module
-- loads, so this must be lazily initialised on first use.
local thisstate
local function get_thisstate()
    if not thisstate then thisstate = ffi.cast("lua_State*", luajr.thisstate()) end
    return thisstate
end



-------------------------
-- 2. LUAJR API BASICS --
-------------------------

-- Create luajr module table
local luajr = {}

-- Make luajr module available for 'require'
function package.preload.luajr()
    return luajr
end

-- TRUE, FALSE, NA, NULL definitions
luajr.TRUE          = R.TRUE
luajr.FALSE         = R.FALSE
luajr.NA_logical_   = R.NA_LOGICAL
luajr.NA_integer_   = R.NA_INTEGER
luajr.NA_real_      = R.NA_REAL
luajr.NA_character_ = R.NA_STRING
luajr.NULL          = R.NilValue

-- Forward declarations
local from_sexp
local to_sexp
local vectorish

-- Buffer for luajr.readline
local buf = nil

-- Readline utility
function luajr.readline(prompt)
    if buf == nil then
        buf = ffi.new("unsigned char[1024]")
    end

    R.FlushConsole()
    R.ReadConsole(prompt or "", buf, 1024, 0)

    -- remove terminating newline, but guard against 0-length string
    local len = ffi.C.strlen(buf)
    return ffi.string(buf, len == 0 and 0 or len - 1)
end

-- Get nparams and isvararg for a Lua function, plus argument names.
-- Called from C++ (luajr_func_info).
function luajr.get_func_info(f)
    local info = debug.getinfo(f, "u")
    local arg_names = {}
    for i = 1, info.nparams do
        arg_names[i] = debug.getlocal(f, i)
    end
    return info.nparams, info.isvararg and 1 or 0, arg_names
end

-- sizeof helper
-- ffi.sizeof() fails if the calculated size is larger than 2^31-1 bytes.
-- We need a special version of ffi.sizeof() for use with vector types in
-- order to be able to work with larger chunks of memory.
local sizeof = function(vtype, nelem)
    return ffi.sizeof(vtype, 1) * nelem
end


---------------------
-- 3. VECTOR TYPES --
---------------------

-- Vector capacity flags
-- TODO document
local byref = -1
local alias = -2

-- Caches for CHARSXP <-> Lua string conversion
local charsxp_read_cache = {}   -- CHARSXP (as double via bit cast) -> Lua string
local charsxp_write_cache = {}  -- Lua string -> CHARSXP

-- Helper: convert CHARSXP to Lua string or NA for reading (cached)
local from_charsxp = function(v)
    if v == R.NA_STRING then return R.NA_STRING end
    local key = tonumber(ffi.cast("uintptr_t", v))
    local s = charsxp_read_cache[key]
    if s == nil then
        s = ffi.string(R.CHAR(v))
        charsxp_read_cache[key] = s
    end
    return s
end

-- Helper: convert Lua string or NA to CHARSXP for writing (cached)
local to_charsxp = function(v)
    if v == R.NA_STRING then return R.NA_STRING end
    local ch = charsxp_write_cache[v]
    if ch == nil then
        ch = R.mkChar(v)
        charsxp_write_cache[v] = ch
    end
    return ch
end

-- Helper: get names attribute if it exists and is STRSXP, else nil
local get_names = function(s)
    local names = R.getAttrib(s, R.NamesSymbol)
    if R.TYPEOF(names) == R.STRSXP then return names end
    return nil
end

-- Metatable for vector type
-- typedef struct { ctype* p; SEXP s; double n; double c; } [vector]_t;
local mt_vector_template = function(ct, stype, notfound, dataptr)
    local vtype = ffi.typeof(ct .. "[?]") -- not used for character

    -- Throw an error on an illegal use of a 'byref' vector
    local byref_error = function(method)
        error("cannot call " .. method .. " on a vector passed by reference", 3)
    end

    -- Type-specific element operations
    local op_readv  -- (self, k) self[k] (with conversion)
    local op_writev -- (self, k, v) self[k] = v (with conversion)
    local op_write  -- (p, s, k, v) self(p,s)[k] = v (raw)
    local op_fillv  -- (p, s, k, v, n) fill n elements of self starting at k with v (with conversion)
    local op_copy   -- (p, s, k, p_src, n) copy n elements into self(p,s)[k], ..., self[k+n-1] from p_src (raw)
    local op_copyv  -- (p, s, k, p_src, n) copy n elements into self(p,s)[k], ..., self[k+n-1] from p_src (with conversion)
    local is_val    -- (v) true if v is a Lua type compatible with the vector
    if stype == R.STRSXP then
        op_readv = function(self, k) return from_charsxp(self.p[k]) end
        op_writev = function(self, k, v) R.SET_STRING_ELT(self.s, k - 1, to_charsxp(v)) end
        op_write = function(p, s, k, v) R.SET_STRING_ELT(s, k - 1, v) end
        op_fillv = function(p, s, k, v, n)
            local ch = to_charsxp(v)
            for i = 0,n-1 do R.SET_STRING_ELT(s, k - 1 + i, ch) end
        end
        op_copy = function(p, s, k, p_src, n)
            for i = 0,n-1 do R.SET_STRING_ELT(s, k - 1 + i, p_src[i + 1]) end
        end
        op_copyv = function(p, s, k, p_src, n)
            for i = 0,n-1 do R.SET_STRING_ELT(s, k - 1 + i, to_charsxp(p_src[i + 1])) end
        end
        is_val = function(v) return type(v) == "string" or v == R.NA_STRING end
    elseif stype == R.VECSXP then
        -- Element of a list is itself a SEXP. On read, wrap based on TYPEOF
        -- and the parent list's mode: byref-list -> byref children (writes
        -- propagate, no resize); alias- or owned-list -> alias children
        -- (COW). The alias/owned uniformity ensures the user experience is
        -- the same across the alias->owned transition that happens when an
        -- alias list is first mutated.
        op_readv = function(self, k)
            return from_sexp(self.p[k], (self.c == byref) and byref or alias)
        end
        op_writev = function(self, k, v) R.SET_VECTOR_ELT(self.s, k - 1, to_sexp(v)) end
        op_write = function(p, s, k, v) R.SET_VECTOR_ELT(s, k - 1, v) end
        op_fillv = function(p, s, k, v, n)
            local sx = to_sexp(v)
            for i = 0,n-1 do R.SET_VECTOR_ELT(s, k - 1 + i, sx) end
        end
        op_copy = function(p, s, k, p_src, n)
            for i = 0,n-1 do R.SET_VECTOR_ELT(s, k - 1 + i, p_src[i + 1]) end
        end
        op_copyv = function(p, s, k, p_src, n)
            for i = 0,n-1 do R.SET_VECTOR_ELT(s, k - 1 + i, to_sexp(p_src[i + 1])) end
        end
        is_val = function(v) return v ~= nil end  -- accept anything coercible
    else
        op_readv = function(self, k) return self.p[k] end
        op_writev = function(self, k, v) self.p[k] = v end
        op_write = function(p, s, k, v) p[k] = v end
        op_fillv = function(p, s, k, v, n)
            for i = 0,n-1 do p[k + i] = v end
        end
        op_copy = function(p, s, k, p_src, n)
            ffi.copy(p + k, p_src + 1, sizeof(vtype, n))
        end
        op_copyv = function(p, s, k, p_src, n)
            for i = 0,n-1 do p[k + i] = p_src[i + 1] end
        end
        is_val = function(v) return type(v) == "number" or type(v) == "boolean" end
    end

    -- Helper function to set vector memory
    -- params = { n }: n elements but don't set
    -- params = { fill, n }: n copies of val
    -- params = { p, n }: n elements from p (offset pointer, 1-based)
    -- params = { copy, n }: elements from copy[i], i = 1 to n
    -- params = { insert, insert_n, outer_p, outer_n }: outer_n elements from
    --   outer_p (offset pointer), leaving gap of insert_n at position insert
    -- params = { erase, erase_last, outer_p, outer_n }: outer_n elements from
    --   outer_p (offset pointer), skipping positions erase..erase_last
    -- returns number of elements in the result
    local set = function(p, s, params)
        local ns, nd = params.names_src, params.names_dst
        if params.fill ~= nil then
            op_fillv(p, s, 1, params.fill, params.n)
        elseif params.p ~= nil then
            op_copy(p, s, 1, params.p, params.n)
            if nd and ns then
                for i = 0, params.n - 1 do R.SET_STRING_ELT(nd, i, R.STRING_ELT(ns, i)) end
            end
        elseif params.copy ~= nil then
            op_copyv(p, s, 1, params.copy, params.n)
            if nd and ns then
                for i = 0, params.n - 1 do R.SET_STRING_ELT(nd, i, R.STRING_ELT(ns, i)) end
            end
        elseif params.insert ~= nil then
            if p == params.outer_p then
                for j = params.outer_n, params.insert, -1 do
                    op_write(p, s, j + params.insert_n, p[j])
                end
                if nd then
                    for j = params.outer_n - 1, params.insert - 1, -1 do
                        R.SET_STRING_ELT(nd, j + params.insert_n, R.STRING_ELT(nd, j))
                    end
                    for j = params.insert - 1, params.insert + params.insert_n - 2 do
                        R.SET_STRING_ELT(nd, j, R.BlankString)
                    end
                end
            else
                op_copy(p, s, 1, params.outer_p, params.insert - 1)
                op_copy(p, s, params.insert + params.insert_n,
                    params.outer_p + params.insert - 1, params.outer_n - params.insert + 1)
                if nd and ns then
                    for i = 0, params.insert - 2 do R.SET_STRING_ELT(nd, i, R.STRING_ELT(ns, i)) end
                    for i = params.insert + params.insert_n - 1, params.insert_n + params.outer_n - 1 do
                        R.SET_STRING_ELT(nd, i, R.STRING_ELT(ns, i - params.insert_n))
                    end
                end
            end
            return params.insert_n + params.outer_n
        elseif params.erase ~= nil then
            if p ~= params.outer_p then
                op_copy(p, s, 1, params.outer_p, params.erase - 1)
            end
            op_copy(p, s, params.erase,
                params.outer_p + params.erase_last,
                params.outer_n - params.erase_last)
            if nd then
                local ndel = params.erase_last - params.erase + 1
                if nd ~= ns then
                    for i = 0, params.erase - 2 do R.SET_STRING_ELT(nd, i, R.STRING_ELT(ns, i)) end
                end
                for i = params.erase - 1, params.outer_n - ndel - 1 do
                    R.SET_STRING_ELT(nd, i, R.STRING_ELT(ns, i + ndel))
                end
            end
            return params.outer_n - (params.erase_last - params.erase + 1)
        elseif params.n == nil then
            error("unsupported parameters in set")
        end
        return params.n
    end

    -- In-place set, replacing self's names from a source SEXP.
    -- names_from: SEXP to read source names from, or nil to clear names.
    local set_inplace = function(self, set_params, names_from)
        local src_names = names_from and get_names(names_from) or nil
        if src_names then
            local dst_names = get_names(self.s)
            if not dst_names then
                dst_names = R.PROTECT(R.allocVector(R.STRSXP, self.c))
                R.setAttrib(self.s, R.NamesSymbol, dst_names)
                R.UNPROTECT(1)
            end
            set_params.names_src = src_names
            set_params.names_dst = dst_names
        else
            R.setAttrib(self.s, R.NamesSymbol, R.NilValue)
        end
        -- Always drop dim/dimnames on in-place replacement, matching the
        -- allocate path (copyMostAttrib also drops these).
        R.setAttrib(self.s, R.DimSymbol, R.NilValue)
        R.setAttrib(self.s, R.DimNamesSymbol, R.NilValue)
        self.n = set(self.p, self.s, set_params)
    end

    -- Helper function to (re)allocate memory
    -- self is the current vector
    -- new_c is the new capacity
    -- set_params gets passed on to set()
    -- names_from: optional SEXP to read source names from (defaults to self.s)
    local allocate = function(self, new_c, set_params, names_from)
        -- ensure not a byref
        if self.c == byref then
            byref_error("reallocate")
        end

        -- allocate new memory
        local new_s = R.allocVector(stype, new_c) -- throws if couldn't allocate
        R.PreserveObject(new_s)
        local new_p = dataptr(new_s) - 1

        -- copy attributes (excludes names, dim, dimnames)
        R.copyMostAttrib(self.s, new_s)

        -- handle names: if source has names, create new names at capacity
        local old_names = get_names(names_from or self.s)
        if old_names and new_c > 0 then
            local new_names = R.PROTECT(R.allocVector(R.STRSXP, new_c))
            R.setAttrib(new_s, R.NamesSymbol, new_names)
            R.UNPROTECT(1)
            set_params.names_src = old_names
            set_params.names_dst = new_names
        end

        -- initialize memory
        self.n = set(new_p, new_s, set_params)

        -- release current sexp
        if self.p ~= nullptr and self.c ~= byref then
            R.ReleaseObject(self.s)
        end

        self.p = new_p
        self.s = new_s
        self.c = new_c
    end

    -- Shift self to make room for insert_n elements at position i,
    -- then copy source names into the gap.
    -- names_from: SEXP whose names fill the gap, or nil for blank.
    local insert_shift = function(self, i, insert_n, names_from)
        if self.n + insert_n <= self.c then
            local names = get_names(self.s)
            self.n = set(self.p, self.s, { insert = i, insert_n = insert_n,
                outer_p = self.p, outer_n = self.n,
                names_src = names, names_dst = names })
        else
            allocate(self, self.n + insert_n, { insert = i, insert_n = insert_n,
                outer_p = self.p, outer_n = self.n })
        end
        local dst_names = get_names(self.s)
        local src_names = names_from and get_names(names_from) or nil
        if dst_names and src_names then
            for j = 0, insert_n - 1 do
                R.SET_STRING_ELT(dst_names, i - 1 + j, R.STRING_ELT(src_names, j))
            end
        end
    end

    -- Methods
    local methods = {
        assign = function(self, a, b)
            if a == nil and b == nil then
                if self.c == byref then
                    if self.n ~= 0 then byref_error("assign") end
                else
                    self:clear()
                end
            elseif type(a) == "number" and (is_val(b) or b == nil) then
                -- a copies of b
                if a < 0 then error("assign: count must be non-negative", 2) end
                if self.c == byref and a ~= self.n then byref_error("assign") end
                if self.c == byref or a <= self.c then
                    set_inplace(self, { fill = b, n = a }, nil)
                else
                    allocate(self, a, { fill = b, n = a }, R.NilValue)
                end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if self.c == byref and a.n ~= self.n then byref_error("assign") end
                if self.c == byref or a.n <= self.c then
                    set_inplace(self, { p = a.p, n = a.n }, a.s)
                else
                    allocate(self, a.n, { p = a.p, n = a.n }, a.s)
                end
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                if self.c == byref and #a ~= self.n then byref_error("assign") end
                local src_sexp = (type(a) ~= "table") and a.s or R.NilValue
                if self.c == byref or #a <= self.c then
                    set_inplace(self, { copy = a, n = #a }, src_sexp)
                else
                    allocate(self, #a, { copy = a, n = #a }, src_sexp)
                end
            else
                error("cannot use vector:assign with argument types " ..
                    type(a) .. ", " .. type(b) .. ".", 2)
            end
        end,

        concat = function(self, sep)
            sep = sep or ","
            local str = ""
            for i = 1, #self do
                if i ~= #self then
                    str = str .. tostring(self[i]) .. sep
                else
                    str = str .. tostring(self[i])
                end
            end
            return str
        end,

        debug_str = function(self)
            if self.c == byref then
                return self.n .. "|byref|" .. self:concat(",")
            elseif self.c == alias then
                return self.n .. "|alias|" .. self:concat(",")
            else
                return self.n .. "|" .. self.c .. "|" .. self:concat(",")
            end
        end,

        -- Capacity
        reserve = function(self, n)
            if type(n) ~= "number" or n < 0 then error("reserve: n must be a non-negative number", 2) end
            if self.c == byref then byref_error("reserve") end
            if n > self.c then
                allocate(self, n, { p = self.p, n = self.n })
            end
        end,

        capacity = function(self)
            if self.c < 0 then
                return self.n
            else
                return self.c
            end
        end,

        shrink_to_fit = function(self)
            if self.n < self.c then
                allocate(self, self.n, { p = self.p, n = self.n })
            end
        end,

        -- Modify
        clear = function(self)
            if self.c == byref then
                byref_error("clear")
            elseif self.c == alias then
                allocate(self, 0, { n = 0 })
            else
                R.setAttrib(self.s, R.NamesSymbol, R.NilValue)
                R.setAttrib(self.s, R.DimSymbol, R.NilValue)
                R.setAttrib(self.s, R.DimNamesSymbol, R.NilValue)
                self.n = 0
            end
        end,

        resize = function(self, n, val)
            if type(n) ~= "number" or n < 0 then error("resize: n must be a non-negative number", 2) end
            if self.c == byref then byref_error("resize") end
            if n < self.n then
                self:erase(n + 1, self.n)
            elseif n > self.n then
                if val ~= nil then
                    self:insert(self.n + 1, n - self.n, val)
                else
                    if n > self.c then
                        allocate(self, n, { p = self.p, n = self.n })
                    end
                    local names = get_names(self.s)
                    if names then
                        for j = self.n, n - 1 do R.SET_STRING_ELT(names, j, R.BlankString) end
                    end
                    self.n = n
                end
            end
        end,

        push_back = function(self, value)
            if value == nil then error("push_back: value must not be nil", 2) end
            if self.c == byref then byref_error("push_back") end
            if self.c == alias then
                allocate(self, math.max(1, self.n * 2), { p = self.p, n = self.n })
            elseif self.c < self.n + 1 then
                allocate(self, math.max(1, self.c * 2), { p = self.p, n = self.n })
            end
            self.n = self.n + 1
            op_writev(self, self.n, value)
            local names = get_names(self.s)
            if names then R.SET_STRING_ELT(names, self.n - 1, R.BlankString) end
        end,

        pop_back = function(self)
            -- NB. C++ std::vector pop_back on empty vector undefined; here a no-op
            if self.c == byref then byref_error("pop_back") end
            if self.n > 0 then
                if self.c == alias then
                    allocate(self, self.n - 1, { erase = self.n, erase_last = self.n, outer_p = self.p, outer_n = self.n })
                else
                    self.n = self.n - 1
                end
            end
        end,

        insert = function(self, i, a, b)
            if self.c == byref then byref_error("insert") end
            if type(i) ~= "number" or i < 1 or i > self.n + 1 then
                error("insert: position must be in range [1, #vec+1]", 2)
            end
            if type(a) == "number" and is_val(b) then
                -- a copies of b
                if a < 0 then error("insert: count must be non-negative", 2) end
                insert_shift(self, i, a, nil)
                for j = i, i+a-1 do op_writev(self, j, b) end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                insert_shift(self, i, #a, a.s)
                op_copy(self.p, self.s, i, a.p, #a)
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                insert_shift(self, i, #a, (type(a) ~= "table") and a.s or R.NilValue)
                for j = 1, #a do op_writev(self, i + j - 1, a[j]) end
            else
                error("cannot use vector:insert with argument types " ..
                    type(a) .. ", " .. type(b) .. ".", 2)
            end
        end,

        erase = function(self, first, last)
            if self.c == byref then byref_error("erase") end
            if last == nil then last = first end
            if type(first) ~= "number" or first < 1 or last > self.n or first > last then
                error("erase: range must satisfy 1 <= first <= last <= #vec", 2)
            end
            local ndel = last - first + 1
            if self.c == alias then
                allocate(self, self.n - ndel, { erase = first, erase_last = last, outer_p = self.p, outer_n = self.n })
            else
                local names = get_names(self.s)
                self.n = set(self.p, self.s, { erase = first, erase_last = last, outer_p = self.p, outer_n = self.n,
                    names_src = names, names_dst = names })
            end
        end,

        detach = function(self)
            allocate(self, self.n, { p = self.p, n = self.n })
        end,

        -- Attributes
        get_attr = function(self, k)
            if type(k) ~= "string" then
                error("can only get string-keyed attributes", 2)
            end
            return from_sexp(R.getAttrib(self.s, R.install(k)))
        end,

        set_attr = function(self, k, v)
            if type(k) ~= "string" then
                error("can only set string-keyed attributes", 2)
            end
            if self.c == alias then self:detach() end
            if k == "names" and luajr.is_character(v) then
                local cap = (self.c >= 0) and self.c or self.n
                if v.n == cap then
                    R.setAttrib(self.s, R.NamesSymbol, v.s)
                else
                    local ns = R.PROTECT(R.allocVector(R.STRSXP, cap))
                    for i = 0, math.min(self.n, v.n) - 1 do
                        R.SET_STRING_ELT(ns, i, R.STRING_ELT(v.s, i))
                    end
                    R.setAttrib(self.s, R.NamesSymbol, ns)
                    R.UNPROTECT(1)
                end
            else
                R.setAttrib(self.s, R.install(k), to_sexp(v))
            end
        end,

        unname = function(self)
            if self.c == alias then self:detach() end
            R.setAttrib(self.s, R.NamesSymbol, R.NilValue)
        end,

        -- Named element access
        find = function(self, name)
            local names = R.getAttrib(self.s, R.NamesSymbol)
            if R.TYPEOF(names) ~= R.STRSXP then return nil end
            local nn = math.min(R.length(names), self.n)
            local p = ffi.cast(sexpp, R.STRING_PTR_RO(names))
            for i = 0, nn - 1 do
                if from_charsxp(p[i]) == name then
                    return i + 1
                end
            end
            return nil
        end,

        get = function(self, name)
            local i = self:find(name)
            if i == nil then return nil end
            return op_readv(self, i)
        end,

        set = function(self, name, v)
            local i = self:find(name)
            if i ~= nil then
                if self.c == alias then self:detach() end
                op_writev(self, i, v)
            else
                if self.c == byref then byref_error("set") end
                self:push_back(v)
                local names = R.getAttrib(self.s, R.NamesSymbol)
                if R.TYPEOF(names) ~= R.STRSXP then -- if no names / invalid names
                    names = R.PROTECT(R.allocVector(R.STRSXP, self.c))
                    R.setAttrib(self.s, R.NamesSymbol, names)
                    R.UNPROTECT(1)
                end
                R.SET_STRING_ELT(names, self.n - 1, to_charsxp(name))
            end
        end
    }

    -- The metatable
    local mt = {
        __new = function(ctype, a, b)
            local self = ffi.new(ctype)
            self.p = nullptr
            self.s = R.NilValue
            if ffi.istype(R.sexp, a) and type(b) == "number" and (b == byref or b == alias) then
                -- direct construction of reference or alias
                self.p = dataptr(a) - 1
                self.s = a
                self.c = b
                self.n = R.length(a)
                -- preserve object if alias
                if self.c == alias then R.PreserveObject(self.s) end
            elseif ffi.istype(R.sexp, a) and b == nil then
                -- direct construction from SEXP alias (by user)
                if R.TYPEOF(a) ~= stype then
                    error("cannot construct " .. ffi.string(R.type2char(stype)) ..
                        " vector from " .. R.type_string(a))
                end
                self.p = dataptr(a) - 1
                self.s = a
                self.c = alias
                self.n = R.length(a)
                R.PreserveObject(self.s)
            elseif a == nil and b == nil then
                -- empty vector
                allocate(self, 0, { n = 0 })
            elseif type(a) == "number" and (is_val(b) or b == nil) then
                -- a copies of b
                if a < 0 then error("cannot construct vector with negative size", 2) end
                allocate(self, a, { fill = b, n = a })
            elseif ffi.istype(ctype, a) and b == nil then
                -- from vector to copy
                allocate(self, a.n, { p = a.p, n = a.n }, a.s)
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                local src_sexp = (type(a) ~= "table") and a.s or R.NilValue
                allocate(self, #a, { copy = a, n = #a }, src_sexp)
            else
                error("cannot construct vector with argument types " ..
                    type(a) .. ", " .. type(b) .. ".", 2)
            end
            return self
        end,

        __gc = function(self)
            if self.p ~= nullptr and self.c ~= byref then
                R.ReleaseObject(self.s)
            end
        end,

        __len = function(self)
            return self.n
        end,

        __index = function(self, k)
            if type(k) == "number" then
                return op_readv(self, k)
            else
                return methods[k]
            end
        end,

        __newindex = function(self, k, v)
            if self.c == alias then self:detach() end
            op_writev(self, k, v)
        end,

        __call = function(self, j)
            -- Resolve j to a 1-based index (or nil if not found / out of bounds)
            local i
            if type(j) == "number" then
                if j >= 1 and j <= #self then i = j end
            elseif type(j) == "string" then
                i = self:find(j)
            else
                error("cannot subset vector with type " .. type(j), 2)
            end
            -- Build length-1 result
            local v = ffi.typeof(self)(1)
            v[1] = i and self[i] or notfound
            -- Copy or set name
            local names = get_names(self.s)
            if names then
                local v_names = R.PROTECT(R.allocVector(R.STRSXP, 1))
                R.SET_STRING_ELT(v_names, 0, i and R.STRING_ELT(names, i - 1) or R.NA_STRING)
                R.setAttrib(v.s, R.NamesSymbol, v_names)
                R.UNPROTECT(1)
            end
            return v
        end,

        __tostring = function(self)
            local limit = 100
            local n = math.min(self.n, limit)
            local ns = get_names(self.s)
            local parts = {}
            local fmt
            if stype == R.VECSXP then
                local tnames = { [R.LGLSXP] = "lgl", [R.INTSXP] = "int",
                    [R.REALSXP] = "num", [R.STRSXP] = "chr", [R.VECSXP] = "list" }
                fmt = function(i)
                    local elem = self.p[i]
                    local tn = tnames[R.TYPEOF(elem)]
                    if tn then return tn .. "[" .. R.length(elem) .. "]"
                    else return ffi.string(R.type2char(R.TYPEOF(elem))) end
                end
            else
                fmt = function(i) return tostring(self[i]) end
            end
            if ns then
                local p = ffi.cast(sexpp, R.STRING_PTR_RO(ns))
                for i = 1, n do parts[i] = from_charsxp(p[i - 1]) .. " = " .. fmt(i) end
            else
                for i = 1, n do parts[i] = fmt(i) end
            end
            if self.n > limit then parts[n + 1] = "... (" .. self.n .. " elements)" end
            return table.concat(parts, ", ")
        end,

        __pairs = function(self)
            return function(t, k)
                k = k + 1
                if k > t.n then
                    return nil
                end
                return k, t[k]
            end, self, 0
        end
    }
    mt.__ipairs = mt.__pairs

    return mt
end

-- Vector type definitions
luajr.logical   = ffi.metatype("logical_t",   mt_vector_template("int",    R.LGLSXP,  R.NA_LOGICAL, R.LOGICAL))
luajr.integer   = ffi.metatype("integer_t",   mt_vector_template("int",    R.INTSXP,  R.NA_INTEGER, R.INTEGER))
luajr.numeric   = ffi.metatype("numeric_t",   mt_vector_template("double", R.REALSXP, R.NA_REAL,    R.REAL))
luajr.character = ffi.metatype("character_t", mt_vector_template("SEXP",   R.STRSXP,  R.NA_STRING,  function(s) return ffi.cast(sexpp, R.STRING_PTR_RO(s)) end))
luajr.list      = ffi.metatype("list_t",      mt_vector_template("SEXP",   R.VECSXP,  R.NilValue,   function(s) return ffi.cast(sexpp, R.DATAPTR_RO(s)) end))

-- Vector type checkers
luajr.is_logical   = function(obj) return ffi.istype(luajr.logical, obj) end
luajr.is_integer   = function(obj) return ffi.istype(luajr.integer, obj) end
luajr.is_numeric   = function(obj) return ffi.istype(luajr.numeric, obj) end
luajr.is_character = function(obj) return ffi.istype(luajr.character, obj) end
luajr.is_list      = function(obj) return ffi.istype(luajr.list, obj) end

-- Typed NA constructors: return length-1 vectors containing NA
luajr.NA_logical   = function() return luajr.logical(1, R.NA_LOGICAL) end
luajr.NA_integer   = function() return luajr.integer(1, R.NA_INTEGER) end
luajr.NA_real      = function() return luajr.numeric(1, R.NA_REAL) end
luajr.NA_character = function() return luajr.character(1, R.NA_STRING) end


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


