-- luajr module

-- CONTENTS --
-- 0. PRELIMINARIES --
-- 1. INTERNAL API --
-- 2. LUAJR API BASICS --
-- 3. VECTOR TYPES --
-- 4. LIST TYPE --
-- 5. PASS TO / RETURN FROM LUA --
-- 6. EXTRA TYPES --
-- 7. DEBUGGER --



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
typedef struct SEXPREC* SEXP;

// Type codes
// See also: ./src/shared.h
enum
{
    // TODO xfer to use R.* types
    NULL_T = 0, //NILSXP,
    LIST_T = 19, //VECSXP,

    LOGICAL_T = 10, //LGLSXP,
    INTEGER_T = 13, //INTSXP,
    NUMERIC_T = 14, //REALSXP,
    CHARACTER_T = 16, //STRSXP,

    SEXP_T = 63, // Generic SEXP
    REFERENCE_T = 64,
    VECTOR_T = 128,

    LOGICAL_R =   LOGICAL_T   | REFERENCE_T,
    INTEGER_R =   INTEGER_T   | REFERENCE_T,
    NUMERIC_R =   NUMERIC_T   | REFERENCE_T,
    CHARACTER_R = CHARACTER_T | REFERENCE_T,
    LOGICAL_V =   LOGICAL_T   | VECTOR_T,
    INTEGER_V =   INTEGER_T   | VECTOR_T,
    NUMERIC_V =   NUMERIC_T   | VECTOR_T,
    CHARACTER_V = CHARACTER_T | VECTOR_T,
};

// Vector types
typedef struct { int* p;    SEXP s; double n; double c; } logical_t;
typedef struct { int* p;    SEXP s; double n; double c; } integer_t;
typedef struct { double* p; SEXP s; double n; double c; } numeric_t;
typedef struct { SEXP* p;   SEXP s; double n; double c; } character_t;

// C functions
void* memcpy(void* dest, const void* src, size_t count);
size_t strlen(const char* str);
]]
local internal = ffi.load(luajr_dylib_path)



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
luajr.TRUE          = 1
luajr.FALSE         = 0
luajr.NA_logical_   = R.NA_LOGICAL
luajr.NA_integer_   = R.NA_INTEGER
luajr.NA_real_      = R.NA_REAL
luajr.NA_character_ = R.NA_STRING
luajr.NULL          = R.NilValue

-- Forward declarations
local sexp_get_attr
local sexp_set_attr
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
    if v == luajr.NA_character_ then return luajr.NA_character_ end
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
    if v == luajr.NA_character_ then return luajr.NA_character_ end
    local ch = charsxp_write_cache[v]
    if ch == nil then
        ch = R.mkChar(v)
        charsxp_write_cache[v] = ch
    end
    return ch
end

-- Metatable for vector type
-- typedef struct { ctype* p; SEXP s; double n; double c; } [vector]_t;
local mt_vector_template = function(is_char, ct, stype, dataptr)
    local vtype = ffi.typeof(ct .. "[?]") -- not used for character

    -- Throw an error on an illegal use of a 'byref' vector
    local byref_error = function(method)
        error("cannot call " .. method .. " on a vector passed by reference", 3)
    end

    -- Type-specific element operations
    local op_read  -- (p, k) p[k] (with conversion)
    local op_write -- (self, k, v) self[k] = v (with conversion)
    local op_set   -- (self, k, v) self[k] = v (raw)
    local op_fill  -- (p, s, k, v, n) fill n elements of self starting at k with v (with conversion)
    local op_copy  -- (p, s, k, p_src, n) copy n elements into self(p,s)[k], ..., self[k+n-1] from p_src (raw)
    local op_copyv -- (p, s, k, p_src, n) copy n elements into self(p,s)[k], ..., self[k+n-1] from p_src (with conversion)
    local is_val   -- (v) true if v is a Lua type compatible with the vector
    if is_char then
        op_read = function(p, k) return from_charsxp(p[k]) end
        op_write = function(self, k, v) R.SET_STRING_ELT(self.s, k - 1, to_charsxp(v)) end
        op_set = function(self, k, v) R.SET_STRING_ELT(self.s, k - 1, v) end
        op_fill = function(p, s, k, v, n)
            local ch = to_charsxp(v)
            for i = 0,n-1 do R.SET_STRING_ELT(s, k - 1 + i, ch) end
        end
        op_copy = function(p, s, k, p_src, n)
            for i = 0,n-1 do R.SET_STRING_ELT(s, k - 1 + i, p_src[i + 1]) end
        end
        op_copyv = function(p, s, k, p_src, n)
            for i = 0,n-1 do R.SET_STRING_ELT(s, k - 1 + i, to_charsxp(p_src[i + 1])) end
        end
        is_val = function(v) return type(v) == "string" or v == luajr.NA_character_ end
    else
        op_read = function(p, k) return p[k] end
        op_write = function(self, k, v) self.p[k] = v end
        op_set = function(self, k, v) self.p[k] = v end
        op_fill = function(p, s, k, v, n)
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
        if params.fill ~= nil then
            op_fill(p, s, 1, params.fill, params.n)
        elseif params.p ~= nil then
            op_copy(p, s, 1, params.p, params.n)
        elseif params.copy ~= nil then
            op_copyv(p, s, 1, params.copy, params.n)
        elseif params.insert ~= nil then
            op_copy(p, s, 1, params.outer_p, params.insert - 1)
            op_copy(p, s, params.insert + params.insert_n,
                params.outer_p + params.insert - 1, params.outer_n - params.insert + 1)
            return params.insert_n + params.outer_n
        elseif params.erase ~= nil then
            op_copy(p, s, 1, params.outer_p, params.erase - 1)
            op_copy(p, s, params.erase,
                params.outer_p + params.erase_last,
                params.outer_n - params.erase_last)
            return params.outer_n - (params.erase_last - params.erase + 1)
        elseif params.n == nil then
            error("unsupported parameters in set")
        end
        return params.n
    end

    -- Helper function to (re)allocate memory
    -- self is the current vector
    -- new_c is the new capacity
    -- set_params gets passed on to set()
    local allocate = function(self, new_c, set_params)
        -- ensure not a byref
        if self.c == byref then
            byref_error("reallocate")
        end

        -- allocate new memory (with array indexing starting at 1)
        local new_s = R.allocVector(stype, new_c) -- throws if couldn't allocate
        R.PreserveObject(new_s)
        local new_p = dataptr(new_s) - 1

        -- copy attributes
        -- NOTE This copies all attributes except names, dim, dimnames. There's no
        -- easy way to know the "right" way of extending these (consider insertion
        -- in the middle, or growing a matrix) so let other methods handle them.
        R.copyMostAttrib(self.s, new_s)
        -- TODO once all the handling of the names attribute is implemented, could
        -- replace the above with:
        -- R.SHALLOW_DUPLICATE_ATTRIB(new_s, self.s)
        -- TODO note the arguments are the other way around; that's correct.

        -- initialize
        self.n = set(new_p, new_s, set_params)

        -- release current sexp
        if self.p ~= nullptr and self.c >= 0 then
            R.ReleaseObject(self.s)
        end

        self.p = new_p
        self.s = new_s
        self.c = new_c
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
                    self.n = set(self.p, self.s, { fill = b, n = a })
                else
                    allocate(self, a, { fill = b, n = a })
                end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if self.c == byref and a.n ~= self.n then byref_error("assign") end
                if self.c == byref or a.n <= self.c then
                    self.n = set(self.p, self.s, { p = a.p, n = a.n })
                else
                    allocate(self, a.n, { p = a.p, n = a.n })
                end
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                if self.c == byref and #a ~= self.n then byref_error("assign") end
                if self.c == byref or #a <= self.c then
                    self.n = set(self.p, self.s, { copy = a, n = #a })
                else
                    allocate(self, #a, { copy = a, n = #a })
                end
            else
                error("cannot use vector:assign with argument types " ..
                    type(a) .. ", " .. type(b) .. ".", 2)
            end
        end,

        print = function(self)
            for k,v in pairs(self) do
                print(k,v)
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
                    self.n = n
                end
            end
        end,

        push_back = function(self, value)
            if value == nil then error("push_back: value must not be nil", 2) end
            if self.c == byref then byref_error("push_back") end
            -- If no capacity, reallocate double the space (min. 1)
            if self.c == alias then
                allocate(self, math.max(1, self.n * 2), { p = self.p, n = self.n })
            elseif self.c < self.n + 1 then
                allocate(self, math.max(1, self.c * 2), { p = self.p, n = self.n })
            end
            self.n = self.n + 1
            op_write(self, self.n, value)
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
                if self.n + a <= self.c then
                    for j = self.n,i,-1 do op_set(self, j + a, self.p[j]) end
                    self.n = self.n + a
                else
                    allocate(self, self.n + a, { insert = i, insert_n = a, outer_p = self.p, outer_n = self.n })
                end
                for j = i,i+a-1 do op_write(self, j, b) end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if self.n + #a <= self.c then
                    for j = self.n,i,-1 do op_set(self, j + #a, self.p[j]) end
                    self.n = self.n + #a
                else
                    allocate(self, self.n + #a, { insert = i, insert_n = #a, outer_p = self.p, outer_n = self.n })
                end
                op_copy(self.p, self.s, i, a.p, #a)
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                if self.n + #a <= self.c then
                    for j = self.n,i,-1 do op_set(self, j + #a, self.p[j]) end
                    self.n = self.n + #a
                else
                    allocate(self, self.n + #a, { insert = i, insert_n = #a, outer_p = self.p, outer_n = self.n })
                end
                for j = 1,#a do op_write(self, i + j - 1, a[j]) end
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
                for j = first, self.n - ndel do op_set(self, j, self.p[j + ndel]) end
                self.n = self.n - ndel
            end
        end,

        detach = function(self)
            allocate(self, self.n, { p = self.p, n = self.n })
        end,

        -- Attributes
        attr = function(self, k, v)
            if type(k) ~= "string" then
                error("Can only set string-keyed attributes.", 2)
            end
            if v == nil then
                return sexp_get_attr(self.s, k)
            else
                sexp_set_attr(self.s, k, v)
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
                -- reference or alias
                self.p = dataptr(a) - 1
                self.s = a
                self.c = b
                self.n = R.length(a)
            elseif a == nil and b == nil then
                -- empty vector
                allocate(self, 0, { n = 0 })
            elseif type(a) == "number" and (is_val(b) or b == nil) then
                -- a copies of b
                if a < 0 then error("cannot construct vector with negative size", 2) end
                allocate(self, a, { fill = b, n = a })
            elseif ffi.istype(ctype, a) and b == nil then
                -- from vector to copy
                allocate(self, a.n, { p = a.p, n = a.n })
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                allocate(self, #a, { copy = a, n = #a })
            else
                error("cannot construct vector with argument types " ..
                    type(a) .. ", " .. type(b) .. ".", 2)
            end
            return self
        end,

        __gc = function(self)
            if self.p ~= nullptr and self.c >= 0 then
                R.ReleaseObject(self.s)
            end
        end,

        __len = function(self)
            return self.n
        end,

        __index = function(self, k)
            if type(k) == "number" then
                return op_read(self.p, k)
            else
                return methods[k]
            end
        end,

        __newindex = function(self, k, v)
            if self.c == alias then
                allocate(self, self.n, { p = self.p, n = self.n })
            end
            op_write(self, k, v)
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
luajr.logical   = ffi.metatype("logical_t",   mt_vector_template(false, "int",    R.LGLSXP,  R.LOGICAL))
luajr.integer   = ffi.metatype("integer_t",   mt_vector_template(false, "int",    R.INTSXP,  R.INTEGER))
luajr.numeric   = ffi.metatype("numeric_t",   mt_vector_template(false, "double", R.REALSXP, R.REAL))
luajr.character = ffi.metatype("character_t", mt_vector_template(true,  "SEXP",   R.STRSXP,  R.STRING_PTR))

-- Vector type checkers
luajr.is_logical   = function(obj) return ffi.istype(luajr.logical, obj) end
luajr.is_integer   = function(obj) return ffi.istype(luajr.integer, obj) end
luajr.is_numeric   = function(obj) return ffi.istype(luajr.numeric, obj) end
luajr.is_character = function(obj) return ffi.istype(luajr.character, obj) end


------------------
-- 4. LIST TYPE --
------------------

-- Metatable for list
local mt_list = {
    __index = function(self, k)
        if type(k) == "number" then
            return self[0][k]
        else
            return self[0][self[0].names[k]]
        end
    end,

    __newindex = function(self, k, v)
        if type(k) == "number" then
            k = math.floor(k)
            if k < 1 or k > #self + 1 then
                error("Assignment out of list bounds.")
            end
            if v == nil then -- erasure
                table.remove(self[0], k)
                for n, j in pairs(self[0].names) do
                    if j == k then self[0].names[n] = nil end
                    if j > k then self[0].names[n] = j - 1 end
                end
            else
                self[0][k] = v
            end
        elseif type(k) == "string" then
            local i = self[0].names[k]
            if i == nil then
                self[0][#self + 1] = v
                self[0].names[k] = #self
            else
                if v == nil then -- erasure
                    table.remove(self[0], i)
                    for n, j in pairs(self[0].names) do
                        if j == i then self[0].names[n] = nil end
                        if j > i then self[0].names[n] = j - 1 end
                    end
                else
                    self[0][i] = v
                end
            end
        else
            error("Invalid key type " .. type(k) .. " in mt_list.__newindex().")
        end
    end,

    __len = function(self)
        return #self[0]
    end,

    __call = function(self, k, v)
        if type(k) ~= "string" then
            error("Can only set string-keyed attributes.")
        end
        if v == nil then
            return self[0][k]
        else
            self[0][k] = v
        end
    end,

    __pairs = function(self)
        -- inverse key lookup
        local inv = {}
        for k,v in pairs(self[0].names) do inv[v] = k end

        return function(t, k)
            -- get j as next numeric key
            local j = 0
            if type(k) == "number" then
                j = k + 1
            else
                j = t[0].names[k] + 1
            end

            -- check for past the end
            if j > #t then
                return nil
            end

            -- get k as either string if avail or integer
            if inv[j] ~= nil then
                k = inv[j]
            else
                k = j
            end

            return k, t[0][j]
        end, self, 0
    end,

    __ipairs = function(self)
        return ipairs(self[0])
    end
}

-- Constructor for list
local new_list = function()
    local list = { [0] = { names = {} } }
    setmetatable(list, mt_list)
    return list
end

-- List definition
luajr.list = new_list

-- List checker
luajr.is_list = function(obj) return getmetatable(obj) == mt_list end


----------------------------------
-- 5. PASS TO / RETURN FROM LUA --
----------------------------------

-- Pass to Lua

-- Identifies vector types from type codes (for pass by reference)
local ref_type = {
    [internal.LOGICAL_R]   = luajr.logical,
    [internal.INTEGER_R]   = luajr.integer,
    [internal.NUMERIC_R]   = luajr.numeric,
    [internal.CHARACTER_R] = luajr.character
}

-- Identifies vector types from type codes (for pass by value / alias)
local vec_type = {
    [internal.LOGICAL_V]   = luajr.logical,
    [internal.INTEGER_V]   = luajr.integer,
    [internal.NUMERIC_V]   = luajr.numeric,
    [internal.CHARACTER_V] = luajr.character
}

-- Construct a reference type. Called with:
--   ud = SEXP to be referenced
--   typecode = e.g. internal.LOGICAL_R, etc
luajr.construct_ref = function(ud, typecode)
    return ref_type[typecode](ffi.cast(R.sexp, ud), byref)
end

-- Construct a vector type (alias / copy-on-write). Called with:
--   ud = SEXP to be aliased
--   typecode = e.g. internal.LOGICAL_V, etc
luajr.construct_vec = function(ud, typecode)
    return vec_type[typecode](ffi.cast(R.sexp, ud), alias)
end

-- Construct a list. Called with:
--   elements = table (integer keys, 1 to n) with elements to hold
--   names = table, e.g. { foo = 1, bar = 3 } if 1st and 3rd elements are named
luajr.construct_list = function(elements, names)
    local list = { [0] = elements }
    list[0].names = names
    setmetatable(list, mt_list)
    return list
end

-- Construct NULL.
luajr.construct_null = function()
    return luajr.NULL
end

-- Construct SEXP.
luajr.construct_sexp = function(ud)
    return R.sexp(ud)
end


-- Return from Lua

-- Helps return luajr objects to R
-- When passed a luajr object, returns two values:
--    1, an integer type code from the internal api
--    2, unused (0) for vector types, or #obj for list, or void* for bare SEXP.
-- If the object is not a luajr type (e.g. a plain Lua type) returns nil, nil.
function luajr.return_info(obj)
    if     luajr.is_logical(obj)        then return internal.LOGICAL_R, 0
    elseif luajr.is_integer(obj)        then return internal.INTEGER_R, 0
    elseif luajr.is_numeric(obj)        then return internal.NUMERIC_R, 0
    elseif luajr.is_character(obj)      then return internal.CHARACTER_R, 0

    elseif luajr.is_list(obj)           then return internal.LIST_T, #obj
    elseif obj == nullptr               then return internal.NULL_T, 0
    elseif obj == luajr.NULL            then return internal.NULL_T, 0
    elseif ffi.istype(R.sexp, obj)      then return internal.SEXP_T, ffi.cast("void*", obj)
    end

    return nil, nil
end

-- Get nparams and isvararg for a Lua function.
-- Called from C (luajr_func_nparams).
function luajr.func_info(f)
    local info = debug.getinfo(f, "u")
    return info.nparams, info.isvararg and 1 or 0
end

-- Combined return for cdata types. Checks type, writes SEXP to ptr if
-- applicable, and returns a typecode. Returns nil for unknown cdata types.
-- Used by the LUA_TCDATA branch in luajr_tosexp (push_to.cpp).
function luajr.return_cdata(obj, ptr)
    if luajr.is_logical(obj) or luajr.is_integer(obj) or
       luajr.is_numeric(obj) or luajr.is_character(obj) then
        obj:shrink_to_fit()
        ffi.cast(voidpp, ptr)[0] = obj.s
    elseif ffi.istype(R.sexp, obj) then
        ffi.cast(voidpp, ptr)[0] = obj
    elseif obj ~= nullptr and obj ~= luajr.NULL then
        error("Cannot return cdata of this type to R.")
    end
end


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


