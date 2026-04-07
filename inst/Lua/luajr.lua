-- luajr module

-- CONTENTS --
-- 0. PRELIMINARIES --
-- 1. INTERNAL API --
-- 2. LUAJR API BASICS --
-- 3. REFERENCE TYPES --
-- 4. VECTOR TYPES --
-- 5. LIST TYPE --
-- 6. PASS TO / RETURN FROM LUA --
-- 7. EXTRA TYPES --
-- 8. DEBUGGER --


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

-- "Hidden" sentinel object for internal use
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

// Reference types
typedef struct { int* _p;    SEXP _s; } logical_rt;
typedef struct { int* _p;    SEXP _s; } integer_rt;
typedef struct { double* _p; SEXP _s; } numeric_rt;
typedef struct { SEXP _s; } character_rt;

// Vector types
typedef struct { int* p;    double n; double c; } logical_vt;
typedef struct { int* p;    double n; double c; } integer_vt;
typedef struct { double* p; double n; double c; } numeric_vt;

// For vector types' manual memory management
void* memcpy(void* dest, const void* src, size_t count);
void* malloc(size_t size);
void free(void* ptr);

// Other C functions
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

-- Malloc and sizeof helpers
-- ffi.sizeof() fails if the calculated size is larger than 2^31-1 bytes,
-- as does ffi.new() (see lj_ctype_vlsize in lj_ctype.c). We use malloc
-- directly for vector allocations, so the limit on ffi.new() does not restrict
-- the size of allocated vector types. But we need a special version of
-- ffi.sizeof() for use with vector types in order to be able to work with
-- larger chunks of memory. We also use a wrapper around ffi.C.malloc() to
-- limit allocation size to 128 GiB, which can be overwritten by changing
-- luajr.max_alloc below.
luajr.max_alloc = 2^37

local malloc = function(size)
    if (size > luajr.max_alloc) then
        error(string.format("Cannot allocate a block larger than " ..
            luajr.max_alloc / 1024^3 .. " GiB. Requested size: " ..
            size / 1024^3 .. " GiB."))
    end
    return ffi.C.malloc(size)
end

local sizeof = function(vtype, nelem)
    return ffi.sizeof(vtype, 1) * nelem
end


------------------------
-- 3. REFERENCE TYPES --
------------------------

-- Reference type allocators
-- R.ReleaseObject is called in garbage collection.

local function alloc_logical(x, size)
    x._s = R.allocVector(R.LGLSXP, size)
    R.PreserveObject(x._s)
    x._p = R.LOGICAL(x._s) - 1
end

local function alloc_integer(x, size)
    x._s = R.allocVector(R.INTSXP, size)
    R.PreserveObject(x._s)
    x._p = R.INTEGER(x._s) - 1
end

local function alloc_numeric(x, size)
    x._s = R.allocVector(R.REALSXP, size)
    R.PreserveObject(x._s)
    x._p = R.REAL(x._s) - 1
end

local function alloc_character(x, size)
    x._s = R.allocVector(R.STRSXP, size)
    R.PreserveObject(x._s)
end

local function alloc_character_NA(x, size)
    x._s = R.allocVector(R.STRSXP, size)
    R.PreserveObject(x._s)
    for i = 0, size - 1 do
        R.SET_STRING_ELT(x._s, i, luajr.NA_character_)
    end
end

local function alloc_character_to(x, size, v)
    x._s = R.allocVector(R.STRSXP, size)
    R.PreserveObject(x._s)
    local sv = R.PROTECT(R.mkChar(v))
    for i = 0, size - 1 do
        R.SET_STRING_ELT(x._s, i, sv)
    end
    R.UNPROTECT(1)
end

-- Metatable for logical/integer/numeric reference types
local mt_basic_r = function(allocator)
    local mt = {
        __new = function(ctype, init1, init2)
            local self = ffi.new(ctype)
            if init1 == hidden then
                -- do nothing
            elseif type(init1) == "number" then
                allocator(self, init1)
                if init2 ~= nil then
                    for i = 1,#self do self._p[i] = init2 end
                end
            elseif vectorish(init1) then
                allocator(self, #init1)
                for i = 1,#self do self._p[i] = init1[i] end
            else
                error("Reference type must be initialised.")
            end
            return self
        end,

        __gc = function(x)
            -- TODO from looking at R_ReleaseObject in memory.c, it seems like calling
            -- this on an object that has not been preserved with R_PreserveObject is
            -- harmless. It may involve a performance penalty, so ideally this could be
            -- removed for pass-by-reference types. Note, same applies to mt_character_r.
            R.ReleaseObject(x._s)
        end,

        __len = function(x)
            return R.length(x._s)
        end,

        __index = function(x, k)
            return x._p[k]
        end,

        __newindex = function(x, k, v)
            x._p[k] = v
        end,

        __call = function(x, k, v)
            if type(k) ~= "string" then
                error("Can only set string-keyed attributes.")
            end
            if v == nil then
                return sexp_get_attr(x._s, k)
            else
                sexp_set_attr(x._s, k, v)
            end
        end,

        __pairs = function(x)
            return function(t, k)
                k = k + 1
                if k > #t then return nil end
                return k, t[k]
            end, x, 0
        end
    }
    mt.__ipairs = mt.__pairs
    return mt
end

-- Metatable for character reference type
local mt_character_r = {
    __new = function(ctype, init1, init2)
        local self = ffi.new(ctype)
        if init1 == hidden then
            -- do nothing
        elseif type(init1) == "number" then
            if init2 == nil then
                alloc_character(self, init1)
            elseif init2 == luajr.NA_character_ then
                alloc_character_NA(self, init1)
            else
                alloc_character_to(self, init1, init2)
            end
        elseif vectorish(init1) then
            alloc_character(self, #init1)
            for i = 1,#self do self[i] = init1[i] end
        else
            error("Reference type must be initialised.")
        end
        return self
    end,

    __gc = function(x)
        R.ReleaseObject(x._s)
    end,

    __len = function(x)
        return R.length(x._s)
    end,

    __index = function(x, k)
        local v = R.STRING_ELT(x._s, k - 1)
        if v == luajr.NA_character_ then
            return v
        else
            return ffi.string(R.CHAR(v))
        end
    end,

    __newindex = function(x, k, v)
        if v == luajr.NA_character_ then
            R.SET_STRING_ELT(x._s, k - 1, luajr.NA_character_)
        else
            R.SET_STRING_ELT(x._s, k - 1, R.mkChar(v))
        end
    end,

    __call = function(x, k, v)
        if type(k) ~= "string" then
            error("Can only set string-keyed attributes.")
        end
        if v == nil then
            return sexp_get_attr(x._s, k)
        else
            sexp_set_attr(x._s, k, v)
        end
    end,

    __pairs = function(x)
        return function(t, k)
            k = k + 1
            if k > #t then return nil end
            return k, t[k]
        end, x, 0
    end
}
mt_character_r.__ipairs = mt_character_r.__pairs


-- Reference type definitions
luajr.logical_r   = ffi.metatype("logical_rt", mt_basic_r(alloc_logical))
luajr.integer_r   = ffi.metatype("integer_rt", mt_basic_r(alloc_integer))
luajr.numeric_r   = ffi.metatype("numeric_rt", mt_basic_r(alloc_numeric))
luajr.character_r = ffi.metatype("character_rt", mt_character_r)

-- Reference type checkers
luajr.is_logical_r   = function(obj) return ffi.istype(luajr.logical_r, obj) end
luajr.is_integer_r   = function(obj) return ffi.istype(luajr.integer_r, obj) end
luajr.is_numeric_r   = function(obj) return ffi.istype(luajr.numeric_r, obj) end
luajr.is_character_r = function(obj) return ffi.istype(luajr.character_r, obj) end


---------------------
-- 4. VECTOR TYPES --
---------------------

-- Helper function to reallocate memory
-- p is the pointer to the memory;
-- vtype is the variable-length array type (e.g. 'double[?]')
-- ptype is the corresponding pointer type (e.g. 'double*')
-- nelem is the new number of elements
-- init1, init2 control initialization of the new memory
local vec_realloc = function(p, vtype, ptype, nelem, init1, init2)
    -- check on nelem
    if nelem < 1 then
        if p ~= nullptr then ffi.C.free(p + 1) end
        return nullptr
    end

    -- allocate new memory (with array indexing starting at 1)
    local new_p = ffi.cast(ptype, malloc(sizeof(vtype, nelem)))
    if new_p == nullptr then
        error("Could not allocate memory in vec_realloc.")
    else
        new_p = new_p - 1
    end

    -- initialize according to init1 and init2
    if init1 == nil and init2 == nil then
        -- do nothing
    elseif (type(init1) == "number" or type(init1) == "boolean") and init2 == nil then
        -- number, nil: fill with number
        for i = 1,nelem do new_p[i] = init1 end
    elseif vectorish(init1) then
        -- table, any: fill with table, only the first init2 entries if provided
        for i = 1,init2 or #init1 do new_p[i] = init1[i] end
    elseif ffi.istype(ptype, init1) then
        -- ptr to data of same type, any: fill, only the first init2 entries if provided
        if init1 ~= nullptr then
            ffi.copy(new_p + 1, init1 + 1, sizeof(vtype, init2 or nelem))
        end
    elseif type(init1) == "number" and type(init2) == "number" then
        -- gapped copy: copy old p to new p, skipping over init2 elements at position init1
        if p ~= nullptr then
            ffi.copy(new_p + 1, p + 1, sizeof(vtype, init1 - 1))
            ffi.copy(new_p + init1 + init2, p + init1, sizeof(vtype, nelem - init1 - init2 + 1))
        end
    else
        error(string.format("Could not interpret initializers to vec_realloc: [%s] %s, [%s] %s",
            type(init1), tostring(init1), type(init2), tostring(init2)))
    end

    -- free current contents of p (with array indexing starting at 1)
    if p ~= nullptr then
        ffi.C.free(p + 1)
    end

    return new_p
end

-- Metatable for logical/integer/numeric vector
local mt_basic_v = function(ct)
    local vtype = ffi.typeof(ct .. "[?]")
    local ptype = ffi.typeof(ct .. "*")

    -- Methods
    -- TODO consistent way of handling bad arguments ... ?
    local methods = {
        assign = function(self, a, b)
            if a == nil and b == nil then
                self.n = 0
            elseif type(a) == "number" and (type(b) == "number" or type(b) == "boolean" or b == nil) then
                -- a copies of b
                if a <= self.c then
                    if b ~= nil then
                        for i = 1,a do self.p[i] = b end
                    end
                    self.n = a
                else
                    self.p = vec_realloc(self.p, vtype, ptype, a, b)
                    self.n = a
                    self.c = a
                end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if a.n <= self.c then
                    ffi.copy(self.p + 1, a.p + 1, sizeof(vtype, a.n))
                    self.n = a.n
                else
                    self.p = vec_realloc(self.p, vtype, ptype, a.n, a.p)
                    self.n = a.n
                    self.c = a.n
                end
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                if #a <= self.c then
                    for i = 1,#a do self.p[i] = a[i] end
                    self.n = #a
                else
                    self.p = vec_realloc(self.p, vtype, ptype, #a, a)
                    self.n = #a
                    self.c = #a
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
            for i=1,#self do
                if sep ~= nil and i ~= #self then
                    str = str .. tostring(self[i]) .. sep
                else
                    str = str .. tostring(self[i])
                end
            end
            return str
        end,

        debug_str = function(self)
            return self.n .. "|" .. self.c .. "|" .. self:concat(",")
        end,

        -- Capacity
        reserve = function(self, n)
            if n == nil then error("must specify new reserved size", 2) end
            if n > self.c then
                self.p = vec_realloc(self.p, vtype, ptype, n, self.p, self.n)
                self.c = n
            end
        end,

        capacity = function(self)
            return self.c
        end,

        shrink_to_fit = function(self)
            if self.n < self.c then
                self.p = vec_realloc(self.p, vtype, ptype, self.n, self.p)
                self.c = self.n
            end
        end,

        -- Modify
        clear = function(self)
            -- Don't reallocate, just shrink to 0
            self.n = 0
        end,

        resize = function(self, n, val)
            if n <= self.n then -- fail if n==nil
                -- If shrinking, just decrease bound
                self.n = n
            elseif n <= self.c then
                -- If enlarging, but still in capacity, copy new values
                if val ~= nil then
                    for i = self.n + 1, n do self.p[i] = val end
                end
                self.n = n
            else
                -- If need to reallocate, do so and copy old contents
                self.p = vec_realloc(self.p, vtype, ptype, n, self.p, self.n)
                if val ~= nil then
                    for i = self.n + 1, n do self.p[i] = val end
                end
                self.n = n
                self.c = n
            end
        end,

        push_back = function(self, val)
            if self.c > self.n then
                -- If capacty allows, just assign new value
                self.p[self.n + 1] = val -- fail if val == nil
                self.n = self.n + 1
            else
                -- Otherwise, reallocate double the space (min. 1)
                local new_c = self.c * 2
                if new_c < 1 then new_c = 1 end
                self.p = vec_realloc(self.p, vtype, ptype, new_c, self.p, self.n)
                self.p[self.n + 1] = val -- fail if val == nil
                self.n = self.n + 1
                self.c = new_c
            end
        end,

        pop_back = function(self)
            -- NB. C++ std::vector pop_back on empty vector undefined; here a no-op
            if self.n > 0 then
                self.n = self.n - 1
            end
        end,

        insert = function(self, i, a, b)
            if i == nil then error("must specify insertion point", 2) end
            if type(a) == "number" and type(b) == "number" then
                -- a copies of b
                if self.n + a <= self.c then
                    for j = self.n,i,-1 do self.p[j + a] = self.p[j] end
                    for j = i,i+a-1 do self.p[j] = b end
                    self.n = self.n + a
                else
                    self.p = vec_realloc(self.p, vtype, ptype, self.n + a, i, a)
                    for j = i,i+a-1 do self.p[j] = b end
                    self.c = self.n + a
                    self.n = self.n + a
                end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if self.n + #a <= self.c then
                    for j = self.n,i,-1 do self.p[j + #a] = self.p[j] end
                    ffi.copy(self.p + i, a.p + 1, sizeof(vtype, #a))
                    self.n = self.n + #a
                else
                    self.p = vec_realloc(self.p, vtype, ptype, self.n + #a, i, #a)
                    ffi.copy(self.p + i, a.p + 1, sizeof(vtype, #a))
                    self.c = self.n + #a
                    self.n = self.n + #a
                end
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                if self.n + #a <= self.c then
                    for j = self.n,i,-1 do self.p[j + #a] = self.p[j] end
                    for j = 1,#a do self.p[j + i - 1] = a[j] end
                    self.n = self.n + #a
                else
                    self.p = vec_realloc(self.p, vtype, ptype, self.n + #a, i, #a)
                    for j = 1,#a do self.p[j + i - 1] = a[j] end
                    self.c = self.n + #a
                    self.n = self.n + #a
                end
            else
                error("cannot use vector:insert with argument types " ..
                    type(a) .. ", " .. type(b) .. ".", 2)
            end
        end,

        erase = function(self, first, last)
            if last == nil then last = first end
            local ndel = last - first + 1
            for i = first, self.n - ndel do self.p[i] = self.p[i + ndel] end
            self.n = self.n - ndel
        end
    }

    -- The metatable
    local mt = {
        __new = function(ctype, a, b)
            local self = ffi.new(ctype)
            if a == nil and b == nil then
                self.p = nullptr
                self.n = 0
                self.c = 0
            elseif type(a) == "number" and (type(b) == "number" or type(b) == "boolean" or b == nil) then
                -- a copies of b
                self.p = vec_realloc(nullptr, vtype, ptype, a, b)
                self.n = a
                self.c = a
            elseif ffi.istype(ctype, a) and b == nil then
                -- from vector to copy
                self.p = vec_realloc(nullptr, vtype, ptype, a.n, a.p)
                self.n = a.n
                self.c = a.n
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                self.p = vec_realloc(nullptr, vtype, ptype, #a, a)
                self.n = #a
                self.c = #a
            else
                error("cannot construct vector with argument types " ..
                    type(a) .. ", " .. type(b) .. ".", 2)
            end
            return self
        end,

        __gc = function(self)
            if self.p ~= nullptr then
                ffi.C.free(self.p + 1)
            end
        end,

        __len = function(self)
            return self.n
        end,

        __index = function(self, k)
            if type(k) == "number" then
                return self.p[k]
            else
                return methods[k]
            end
        end,

        __newindex = function(self, k, v)
            self.p[k] = v
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

-- For keeping strings in luajr.character
local tostring2 = function(v)
    if v == luajr.NA_character_ then
        return luajr.NA_character_
    elseif v == nil then
        return ""
    else
        return tostring(v)
    end
end

-- Metatable for character vector
local mt_character_v
local new_character_v
mt_character_v = {
    __index = function(self, k)
        if type(k) == "number" then
            return rawget(self, 0)[k]
        else
            return mt_character_v[k]
        end
    end,

    __newindex = function(self, k, v)
        rawget(self, 0)[k] = tostring2(v)
    end,

    __len = function(self)
        return #(rawget(self, 0))
    end,

    __pairs = function(self)
        return pairs(rawget(self, 0))
    end,

    __ipairs = function(self)
        return ipairs(rawget(self, 0))
    end,

    assign = function(self, a, b)
        nt = new_character_v(a, b)
        self:resize(#nt)
        for i = 1,#self do rawget(self, 0)[i] = rawget(nt, 0)[i] end
    end,

    print = function(self)
        for k,v in pairs(self) do
            print(k,v)
        end
    end,

    concat = function(self, sep)
        sep = sep or ","
        local str = ""
        for i = 1,#self do
            v = rawget(self, 0)[i]
            if v == luajr.NA_character_ then str = str .. "NA" else str = str .. v end
            if i < #self then str = str .. sep end
        end
        return str
    end,

    debug_str = function(self)
        return #self .. "|" .. #self .. "|" .. self:concat(",")
    end,

    -- Capacity
    reserve = function(self, n) end,
    capacity = function(self) return #self end,
    shrink_to_fit = function(self) end,

    -- Modify
    clear = function(self)
        table.clear(rawget(self, 0))
    end,

    resize = function(self, n, val)
        if n < #self then
            for i = 1, #self - n do table.remove(rawget(self, 0)) end
        else
            for i = 1, n - #self do table.insert(rawget(self, 0), tostring2(val)) end
        end
    end,

    push_back = function(self, val)
        table.insert(rawget(self, 0), tostring2(val))
    end,

    pop_back = function(self)
        table.remove(rawget(self, 0))
    end,

    insert = function(self, i, a, b)
        nt = new_character_v(a, b)
        for j = #self,i,-1 do rawget(self, 0)[j + #nt] = rawget(self, 0)[j] end
        for j = 1,#nt do rawget(self, 0)[j + i - 1] = nt[j] end
    end,

    erase = function(self, first, last)
        if last == nil then last = first end
        local ndel = last - first + 1
        for i = first, #self - ndel do rawget(self, 0)[i] = rawget(self, 0)[i + ndel] end
        for i = 1, ndel do table.remove(rawget(self, 0)) end
    end
}

-- Constructor for character_v
new_character_v = function(a, b)
    local t
    if a == nil and b == nil then
        t = {}
    elseif type(a) == "number" then
        -- a copies of b
        t = table.new(a, 0)
        for i=1,a do t[i] = tostring2(b) end
    elseif getmetatable(a) == mt_character_v and b == nil then
        -- from vector to copy
        t = table.new(#a, 0)
        for i=1,#a do t[i] = a[i] end
    elseif vectorish(a) and b == nil then
        -- from vector-ish object
        t = table.new(#a, 0)
        for i=1,#a do t[i] = tostring2(a[i]) end
    else
        error("cannot construct character vector with argument types " ..
            type(a) .. ", " .. type(b) .. ".", 2)
    end
    local vec = { [0] = t }
    setmetatable(vec, mt_character_v)
    return vec
end

-- Vector type definitions
luajr.logical = ffi.metatype("logical_vt", mt_basic_v("int"))
luajr.integer = ffi.metatype("integer_vt", mt_basic_v("int"))
luajr.numeric = ffi.metatype("numeric_vt", mt_basic_v("double"))
luajr.character = new_character_v

-- Vector type checkers
luajr.is_logical   = function(obj) return ffi.istype(luajr.logical, obj) end
luajr.is_integer   = function(obj) return ffi.istype(luajr.integer, obj) end
luajr.is_numeric   = function(obj) return ffi.istype(luajr.numeric, obj) end
luajr.is_character = function(obj) return getmetatable(obj) == mt_character_v end


------------------
-- 5. LIST TYPE --
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
-- 6. PASS TO / RETURN FROM LUA --
----------------------------------

-- Pass to Lua

-- Identifies reference types from type codes
local ref_type = {
    [internal.LOGICAL_R]   = luajr.logical_r,
    [internal.INTEGER_R]   = luajr.integer_r,
    [internal.NUMERIC_R]   = luajr.numeric_r,
    [internal.CHARACTER_R] = luajr.character_r
}

-- Helpers to set reference objects to existing R objects when passing in
local ref_set = {
    [internal.LOGICAL_R]   = function(x, s) x._p, x._s = R.LOGICAL(s) - 1, s end,
    [internal.INTEGER_R]   = function(x, s) x._p, x._s = R.INTEGER(s) - 1, s end,
    [internal.NUMERIC_R]   = function(x, s) x._p, x._s = R.REAL(s) - 1, s end,
    [internal.CHARACTER_R] = function(x, s) x._s = s end
}

-- Identifies vector types from type codes
local vec_type = {
    [internal.LOGICAL_V]   = luajr.logical,
    [internal.INTEGER_V]   = luajr.integer,
    [internal.NUMERIC_V]   = luajr.numeric
    -- CHARACTER_V handled separately
}

-- Helpers to copy existing R objects to vector objects when passing in
local vec_set = {
    [internal.LOGICAL_V]   = function(x, s) internal.memcpy(x.p + 1, R.LOGICAL(s), ffi.sizeof("int") * R.length(s)) end,
    [internal.INTEGER_V]   = function(x, s) internal.memcpy(x.p + 1, R.INTEGER(s), ffi.sizeof("int") * R.length(s)) end,
    [internal.NUMERIC_V]   = function(x, s) internal.memcpy(x.p + 1, R.REAL(s), ffi.sizeof("double") * R.length(s)) end
    -- CHARACTER_V handled separately
}


-- Construct a reference type. Called with:
--   ud = SEXP to be referenced
--   typecode = e.g. internal.LOGICAL_R, etc
luajr.construct_ref = function(ud, typecode)
    local x = ref_type[typecode](hidden)
    ref_set[typecode](x, ffi.cast(R.sexp, ud))
    return x
end

-- Construct a vector type. Called with:
--   ud = SEXP to be copied
--   typecode = e.g. internal.LOGICAL_V, etc
luajr.construct_vec = function(ud, typecode)
    if typecode == internal.CHARACTER_V then
        local x = luajr.character(R.length(ud), "")
        for i = 1,#x do
            local v = R.STRING_ELT(ud, i - 1)
            if v == luajr.NA_character_ then
                x[i] = v
            else
                x[i] = ffi.string(R.CHAR(v))
            end
        end
        return x
    else
        local x = vec_type[typecode](R.length(ud), 0)
        vec_set[typecode](x, ud)
        return x
    end
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
--    2, a pointer to the object's internal SEXP, if the object is a reference;
--       or the number of elements in that object, if the object is a vector/list.
-- If the object is not a luajr type (e.g. a plain Lua type) returns nil, nil.
function luajr.return_info(obj)
    if     luajr.is_logical_r(obj)      then return internal.LOGICAL_R, ffi.cast("void*", obj._s)
    elseif luajr.is_integer_r(obj)      then return internal.INTEGER_R, ffi.cast("void*", obj._s)
    elseif luajr.is_numeric_r(obj)      then return internal.NUMERIC_R, ffi.cast("void*", obj._s)
    elseif luajr.is_character_r(obj)    then return internal.CHARACTER_R, ffi.cast("void*", obj._s)

    elseif luajr.is_logical(obj)        then return internal.LOGICAL_V, #obj
    elseif luajr.is_integer(obj)        then return internal.INTEGER_V, #obj
    elseif luajr.is_numeric(obj)        then return internal.NUMERIC_V, #obj
    elseif luajr.is_character(obj)      then return internal.CHARACTER_V, #obj
    elseif luajr.is_list(obj)           then return internal.LIST_T, #obj
    elseif obj == nullptr               then return internal.NULL_T, 0
    elseif obj == luajr.NULL            then return internal.NULL_T, 0
    elseif ffi.istype(R.sexp, obj)      then return internal.SEXP_T, ffi.cast("void*", obj)
    end

    return nil, nil
end

-- Copies a luajr object to allocated memory so that it can be taken in by R.
--   obj is the luajr object;
--   ptr is a SEXP* (_pointer_ to SEXP) if obj is a reference type;
--     or the start of some contiguous memory if obj is a basic vector type;
--     or a SEXP if obj is a character vector.
function luajr.return_copy(obj, ptr)
    if luajr.is_logical_r(obj) or luajr.is_integer_r(obj) or
       luajr.is_numeric_r(obj) or luajr.is_character_r(obj) then
        ffi.cast(voidpp, ptr)[0] = obj._s
    elseif ffi.istype(R.sexp, obj) then
        ffi.cast(voidpp, ptr)[0] = obj
    elseif luajr.is_logical(obj) then
        ffi.copy(ffi.cast("int*", ptr), obj.p + 1, sizeof("int[?]", obj.n))
    elseif luajr.is_integer(obj) then
        ffi.copy(ffi.cast("int*", ptr), obj.p + 1, sizeof("int[?]", obj.n))
    elseif luajr.is_numeric(obj) then
        ffi.copy(ffi.cast("double*", ptr), obj.p + 1, sizeof("double[?]", obj.n))
    elseif luajr.is_character(obj) then
        local s = ffi.cast("SEXP", ptr)
        for k,v in ipairs(obj) do
            if v == luajr.NA_character_ then
                R.SET_STRING_ELT(s, k - 1, luajr.NA_character_)
            else
                R.SET_STRING_ELT(s, k - 1, R.mkChar(v))
            end
        end
    else
        error("luajr.return_copy should not be called with an object of this type.")
    end
end


--------------------
-- 7. EXTRA TYPES --
--------------------

-- Attribute set/getters
sexp_get_attr = function(s, k)
    local a = R.getAttrib(s, R.install(k))
    local t = R.TYPEOF(a)
    if t == R.NILSXP then return nil end
    local x
    if t == R.LGLSXP then
        x = luajr.logical_r(hidden)
        x._p, x._s = R.LOGICAL(a) - 1, a
    elseif t == R.INTSXP then
        x = luajr.integer_r(hidden)
        x._p, x._s = R.INTEGER(a) - 1, a
    elseif t == R.REALSXP then
        x = luajr.numeric_r(hidden)
        x._p, x._s = R.REAL(a) - 1, a
    elseif t == R.STRSXP then
        x = luajr.character_r(hidden)
        x._s = a
    else
        error("Cannot get attribute of type " .. R.type_string(a))
    end
    return x
end

sexp_set_attr = function(s, k, v)
    if k == "/matrix/colnames" and luajr.is_character_r(v) then
        local dimnames = R.allocVector(R.VECSXP, 2)
        R.PROTECT(dimnames)
        R.SET_VECTOR_ELT(dimnames, 0, R.NilValue)
        R.SET_VECTOR_ELT(dimnames, 1, v._s)
        R.dimnamesgets(s, dimnames)
        R.UNPROTECT(1)
    elseif luajr.is_logical_r(v) or luajr.is_integer_r(v) or
           luajr.is_numeric_r(v) or luajr.is_character_r(v) then
        R.setAttrib(s, R.install(k), v._s)
    else
        error("No attribute setter for type " .. type(v) .. ".")
    end
end

-- Does obj have indexing and length capabilities?
vectorish = function(obj)
    -- luajr.character is a table, so there is no separate check for that type
    return type(obj) == "table" or luajr.is_numeric_r(obj) or luajr.is_numeric(obj) or
        luajr.is_integer_r(obj) or luajr.is_integer(obj) or luajr.is_character_r(obj) or
        luajr.is_logical_r(obj) or luajr.is_logical(obj)
end

-- dataframe type
function luajr.dataframe()
    local df = luajr.list()
    df[0].class = "data.frame"

    return df
end

-- matrix reference type: specify nrow and ncol
function luajr.matrix_r(nrow, ncol)
    local m = luajr.numeric_r(nrow * ncol, 0.0)

    -- Make dimensions
    local dim = luajr.integer_r(2)
    dim[1] = nrow
    dim[2] = ncol
    m("dim", dim)

    return m
end

-- datamatrix reference type: specify nrow, ncol, and column names
function luajr.datamatrix_r(nrow, ncol, names)
    local m = luajr.matrix_r(nrow, ncol)

    -- Make column names
    if #names > ncol then error("Supplied more names than columns to luajr.datamatrix_r.") end
    local colnames = luajr.character_r(ncol)
    for i = 1,#names do colnames[i] = names[i] end
    m("/matrix/colnames", colnames)

    return m
end


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


