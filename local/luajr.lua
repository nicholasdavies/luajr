-- luajr module

-- CONTENTS --
-- 0. PRELIMINARIES --
-- 1. INTERNAL API --
-- 2. LUAJR API BASICS --
-- 3. REFERENCE TYPES --
-- 4. VECTOR TYPES --
-- 5. LIST TYPE --
-- 6. PASS TO LUA --
-- 7. RETURN TO R --
-- 8. EXTRA TYPES --


----------------------
-- 0. PRELIMINARIES --
----------------------

-- Load ffi module
local ffi = require("ffi")

-- Load additional convenience functions for tables (provided by LuaJIT)
table.new = require("table.new")
table.clear = require("table.clear")

-- Script receives the path to the luajr R package dylib as argument
local luajr_dylib_path = ({...})[1]

-- Null pointer object
local nullptr = ffi.cast("void*", 0)


---------------------
-- 1. INTERNAL API --
---------------------

-- Load 'internal' API for interfacing with R (see ./src/lua_ffi.cpp)
ffi.cdef[[
// Forward declarations
struct SEXPREC;
typedef struct SEXPREC* SEXP;

// Type codes
enum
{
    LOGICAL_R = 0, INTEGER_R = 1, NUMERIC_R = 2, CHARACTER_R = 3,
    LOGICAL_V = 4, INTEGER_V = 5, NUMERIC_V = 6, CHARACTER_V = 7,
    LIST_T = 8, NULL_T = 16
};

// Reference types
typedef struct { int* _p;    SEXP _s; } logical_rt;
typedef struct { int* _p;    SEXP _s; } integer_rt;
typedef struct { double* _p; SEXP _s; } numeric_rt;
typedef struct { SEXP _s; } character_rt;

// Vector types
typedef struct { int* p;    uint32_t n; uint32_t c; } logical_vt;
typedef struct { int* p;    uint32_t n; uint32_t c; } integer_vt;
typedef struct { double* p; uint32_t n; uint32_t c; } numeric_vt;

// NA values
extern int TRUE_logical;
extern int FALSE_logical;
extern int NA_logical;
extern int NA_integer;
extern double NA_real;
extern SEXP NA_character;

// Functions to populate reference types
void SetLogicalRef(logical_rt* x, SEXP s);
void SetIntegerRef(integer_rt* x, SEXP s);
void SetNumericRef(numeric_rt* x, SEXP s);
void SetCharacterRef(character_rt* x, SEXP s);

// Functions to allocate reference types
// The Alloc* functions call R_PreserveObject() on the underlying SEXP, so we
// call Release in garbage collection for the corresponding R_ReleaseObject().
void AllocLogical(logical_rt* x, size_t size);
void AllocInteger(integer_rt* x, size_t size);
void AllocNumeric(numeric_rt* x, size_t size);
void AllocCharacter(character_rt* x, size_t size);
void AllocCharacterTo(character_rt* x, size_t size, const char* v);
void Release(SEXP s);

// Functions to populate vector types
void SetLogicalVec(logical_vt* x, SEXP s);
void SetIntegerVec(integer_vt* x, SEXP s);
void SetNumericVec(numeric_vt* x, SEXP s);
// character handled separately

// Functions to get attributes
int GetAttrType(SEXP s, const char* k);
SEXP GetAttrSEXP(SEXP s, const char* k);

// Functions to set attributes
void SetAttrLogicalRef(SEXP s, const char* k, logical_rt* v);
void SetAttrIntegerRef(SEXP s, const char* k, integer_rt* v);
void SetAttrNumericRef(SEXP s, const char* k, numeric_rt* v);
void SetAttrCharacterRef(SEXP s, const char* k, character_rt* v);
void SetMatrixColnamesCharacterRef(SEXP s, character_rt* v);

// To get/set string vectors
const char* GetCharacterElt(SEXP s, ptrdiff_t k);
void SetCharacterElt(SEXP s, ptrdiff_t k, const char* v);

// Set *ptr = val
void SetPtr(void** ptr, void* val);

// Returns length of object s; returns as a double to be larger than 32-bit,
// but still compatible with Lua's single number type.
double SEXP_length(SEXP s);

// Returns 1:nrow as an altrep
SEXP CompactRowNames(size_t nrow);

// For vector types' manual memory management
void* malloc(size_t size);
void free(void* ptr);
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

-- TRUE, FALSE, NA definitions
luajr.TRUE          = internal.TRUE_logical;
luajr.FALSE         = internal.FALSE_logical;
luajr.NA_logical_   = internal.NA_logical;
luajr.NA_integer_   = internal.NA_integer;
luajr.NA_real_      = internal.NA_real;
luajr.NA_character_ = internal.NA_character;

-- Forward declarations of attribute set/getters
local sexp_get_attr
local sexp_set_attr


------------------------
-- 3. REFERENCE TYPES --
------------------------

-- Metatable for logical/integer/numeric reference types
local mt_basic_r = function(allocator)
    local mt = {
        __new = function(ctype, init1, init2)
            local self = ffi.new(ctype)
            if init1 == nullptr then
                -- do nothing
            elseif type(init1) == "number" then
                allocator(self, init1)
                if init2 ~= nil then
                    for i = 1,#self do self._p[i] = init2 end
                end
            elseif #init1 ~= nil then
                allocator(self, #init1)
                for i = 1,#self do self._p[i] = init1[i] end
            else
                error("Reference type must be initialised.")
            end -- TODO copy from existing vector
            return self
        end,

        __gc = function(x)
            -- TODO from looking at R_ReleaseObject in memory.c, it seems like calling
            -- this on an object that has not been preserved with R_PreserveObject is
            -- harmless. It may involve a performance penalty, so ideally this could be
            -- removed for pass-by-reference types. Note, same applies to mt_character_r.
            internal.Release(x._s)
        end,

        __len = function(x)
            return internal.SEXP_length(x._s)
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
        if init1 == nullptr then
            -- do nothing
        elseif type(init1) == "number" then
            if init2 == nil then
                internal.AllocCharacter(self, init1)
            else
                internal.AllocCharacterTo(self, init1, init2)
            end
        elseif #init1 ~= nil then
            allocator(self, #init1)
            for i = 1,#self do self[i] = init1[i] end
        else
            error("Reference type must be initialised.")
        end -- TODO copy from existing vector
        return self
    end,

    __gc = function(x)
        internal.Release(x._s)
    end,

    __len = function(x)
        return internal.SEXP_length(x._s)
    end,

    __index = function(x, k)
        return ffi.string(internal.GetCharacterElt(x._s, k - 1))
    end,

    __newindex = function(x, k, v)
        internal.SetCharacterElt(x._s, k - 1, v)
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
luajr.logical_r   = ffi.metatype("logical_rt", mt_basic_r(internal.AllocLogical))
luajr.integer_r   = ffi.metatype("integer_rt", mt_basic_r(internal.AllocInteger))
luajr.numeric_r   = ffi.metatype("numeric_rt", mt_basic_r(internal.AllocNumeric))
luajr.character_r = ffi.metatype("character_rt", mt_character_r)


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
    local new_p = ffi.cast(ptype, ffi.C.malloc(ffi.sizeof(vtype, nelem)))
    if new_p == nullptr then
        error("Could not allocate memory in vec_realloc.")
    else
        new_p = new_p - 1
    end

    -- initialize according to init1 and init2
    if (type(init1) == "number" or type(init1) == "boolean") and init2 == nil then
        -- number, nil: fill with number
        for i = 1,nelem do new_p[i] = init1 end
    elseif type(init1) == "table" then
        -- table, any: fill with table, only the first init2 entries if provided
        for i = 1,init2 or #init1 do new_p[i] = init1[i] end
    elseif ffi.istype(ptype, init1) then
        -- ptr to data of same type, any: fill, only the first init2 entries if provided
        if init1 ~= nullptr then
            ffi.copy(new_p + 1, init1 + 1, ffi.sizeof(vtype, init2 or nelem))
        end
    elseif type(init1) == "number" and type(init2) == "number" then
        -- gapped copy: copy old p to new p, skipping over init2 elements at position init1
        if p ~= nullptr then
            ffi.copy(new_p + 1, p + 1, ffi.sizeof(vtype, init1 - 1))
            ffi.copy(new_p + init1 + init2, p + init1, ffi.sizeof(vtype, nelem - init1 - init2 + 1))
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
            elseif type(a) == "number" and (type(b) == "number" or type(b) == "boolean") then
                -- a copies of b
                if a <= self.c then
                    for i = 1,a do self.p[i] = b end
                    self.n = a
                else
                    self.p = vec_realloc(self.p, vtype, ptype, a, b)
                    self.n = a
                    self.c = a
                end
            elseif type(a) == "table" and b == nil then
                -- from table initializer
                if #a <= self.c then
                    for i = 1,#a do self.p[i] = a[i] end
                    self.n = #a
                else
                    self.p = vec_realloc(self.p, vtype, ptype, #a, a)
                    self.n = #a
                    self.c = #a
                end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if a.n <= self.c then
                    ffi.copy(self.p + 1, a.p + 1, ffi.sizeof(vtype, a.n))
                    self.n = a.n
                else
                    self.p = vec_realloc(self.p, vtype, ptype, a.n, a.p)
                    self.n = a.n
                    self.c = a.n
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
            elseif type(a) == "table" and b == nil then
                -- from table initializer
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
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if self.n + #a <= self.c then
                    for j = self.n,i,-1 do self.p[j + #a] = self.p[j] end
                    ffi.copy(self.p + i, a.p + 1, ffi.sizeof(vtype, #a))
                    self.n = self.n + #a
                else
                    self.p = vec_realloc(self.p, vtype, ptype, self.n + #a, i, #a)
                    ffi.copy(self.p + i, a.p + 1, ffi.sizeof(vtype, #a))
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
            elseif type(a) == "number" and (type(b) == "number" or type(b) == "boolean") then
                -- a copies of b
                self.p = vec_realloc(nullptr, vtype, ptype, a, b)
                self.n = a
                self.c = a
            elseif type(a) == "table" and b == nil then
                -- from table initializer
                self.p = vec_realloc(nullptr, vtype, ptype, #a, a)
                self.n = #a
                self.c = #a
            elseif ffi.istype(ctype, a) and b == nil then
                -- from vector to copy
                self.p = vec_realloc(nullptr, vtype, ptype, a.n, a.p)
                self.n = a.n
                self.c = a.n
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
    elseif type(a) == "table" and b == nil then
        -- from table initializer
        t = table.new(#a, 0)
        for i=1,#a do t[i] = tostring2(a[i]) end
    elseif getmetatable(a) == mt_character_v and b == nil then
        -- from vector to copy
        t = table.new(#a, 0)
        for i=1,#a do t[i] = a[i] end
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


--------------------
-- 6. PASS TO LUA --
--------------------

-- Identifies reference types from type codes
local ref_type = {
    [internal.LOGICAL_R]   = luajr.logical_r,
    [internal.INTEGER_R]   = luajr.integer_r,
    [internal.NUMERIC_R]   = luajr.numeric_r,
    [internal.CHARACTER_R] = luajr.character_r
}

-- Helpers to set reference objects to existing R objects when passing in
local ref_set = {
    [internal.LOGICAL_R]   = internal.SetLogicalRef,
    [internal.INTEGER_R]   = internal.SetIntegerRef,
    [internal.NUMERIC_R]   = internal.SetNumericRef,
    [internal.CHARACTER_R] = internal.SetCharacterRef
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
    [internal.LOGICAL_V]   = internal.SetLogicalVec,
    [internal.INTEGER_V]   = internal.SetIntegerVec,
    [internal.NUMERIC_V]   = internal.SetNumericVec
    -- CHARACTER_V handled separately
}

-- Construct a reference type. Called with:
--   ud = SEXP to be referenced
--   typecode = e.g. internal.LOGICAL_R, etc
luajr.construct_ref = function(ud, typecode)
    local x = ref_type[typecode](nullptr)
    ref_set[typecode](x, ud)
    return x
end

-- Construct a vector type. Called with:
--   ud = SEXP to be copied
--   typecode = e.g. internal.LOGICAL_V, etc
luajr.construct_vec = function(ud, typecode)
    if typecode == internal.CHARACTER_V then
        local x = luajr.character(internal.SEXP_length(ud), "")
        for i = 1,#x do
            local c = internal.GetCharacterElt(ud, i - 1)
            if c == nullptr then
                x[i] = luajr.NA_character_
            else
                x[i] = ffi.string(c)
            end
        end
        return x
    else
        local x = vec_type[typecode](internal.SEXP_length(ud), 0)
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


--------------------
-- 7. RETURN TO R --
--------------------

-- Helps return luajr objects to R
-- When passed a luajr object, returns two values:
--    1, an integer type code from the internal api
--    2, a pointer to the object's internal SEXP, if the object is a reference;
--       or the number of elements in that object, if the object is a vector/list.
-- If the object is not a luajr type (e.g. a plain Lua type) returns nil, nil.
function luajr.return_info(obj)
    if ffi.istype(luajr.logical_r, obj)        then return internal.LOGICAL_R, ffi.cast("void*", obj._s)
    elseif ffi.istype(luajr.integer_r, obj)    then return internal.INTEGER_R, ffi.cast("void*", obj._s)
    elseif ffi.istype(luajr.numeric_r, obj)    then return internal.NUMERIC_R, ffi.cast("void*", obj._s)
    elseif ffi.istype(luajr.character_r, obj)  then return internal.CHARACTER_R, ffi.cast("void*", obj._s)

    elseif ffi.istype(luajr.logical, obj)      then return internal.LOGICAL_V, #obj
    elseif ffi.istype(luajr.integer, obj)      then return internal.INTEGER_V, #obj
    elseif ffi.istype(luajr.numeric, obj)      then return internal.NUMERIC_V, #obj
    elseif getmetatable(obj) == mt_character_v then return internal.CHARACTER_V, #obj
    elseif getmetatable(obj) == mt_list        then return internal.LIST_T, #obj
    elseif obj == nullptr                      then return internal.NULL_T, 0
    end

    return nil, nil
end

-- Copies a luajr object to allocated memory so that it can be taken in by R.
--   obj is the luajr object;
--   ptr is a SEXP* (_pointer_ to SEXP) if obj is a reference type;
--     or the start of some contiguous memory if obj is a basic vector type;
--     or a SEXP if obj is a character vector.
function luajr.return_copy(obj, ptr)
    if ffi.istype(luajr.logical_r, obj) or ffi.istype(luajr.integer_r, obj) or
       ffi.istype(luajr.numeric_r, obj) or ffi.istype(luajr.character_r, obj) then
        internal.SetPtr(ptr, obj._s)
    elseif ffi.istype(luajr.logical, obj) then
        ffi.copy(ffi.cast("int*", ptr), obj.p + 1, ffi.sizeof("int[?]", obj.n))
    elseif ffi.istype(luajr.integer, obj) then
        ffi.copy(ffi.cast("int*", ptr), obj.p + 1, ffi.sizeof("int[?]", obj.n))
    elseif ffi.istype(luajr.numeric, obj) then
        ffi.copy(ffi.cast("double*", ptr), obj.p + 1, ffi.sizeof("double[?]", obj.n))
    elseif getmetatable(obj) == mt_character_v then
        for k,v in ipairs(obj) do
            if v == luajr.NA_character_ then
                internal.SetCharacterElt(ffi.cast("SEXP", ptr), k - 1, nullptr)
            else
                internal.SetCharacterElt(ffi.cast("SEXP", ptr), k - 1, v)
            end
        end
    else
        error("luajr.return_copy should not be called with an object of this type.")
    end
end


--------------------
-- 8. EXTRA TYPES --
--------------------

-- Attribute set/getters
sexp_get_attr = function(s, k)
    local typecode = internal.GetAttrType(s, k)
    if typecode == internal.NULL_T then return nil end
    local x = ref_type[typecode](nullptr)
    ref_set[typecode](x, internal.GetAttrSEXP(s, k))
    return x
end

sexp_set_attr = function(s, k, v)
    if k == "/matrix/colnames" and ffi.istype(luajr.character_r, v) then
        internal.SetMatrixColnamesCharacterRef(s, v)
    elseif ffi.istype(luajr.logical_r, v) then
        internal.SetAttrLogicalRef(s, k, v)
    elseif ffi.istype(luajr.integer_r, v) then
        internal.SetAttrIntegerRef(s, k, v)
    elseif ffi.istype(luajr.numeric_r, v) then
        internal.SetAttrNumericRef(s, k, v)
    elseif ffi.istype(luajr.character_r, v) then
        internal.SetAttrCharacterRef(s, k, v)
    else
        error("No attribute setter for type " .. type(v) .. ".")
    end
end

-- dataframe type: specify number of rows
function luajr.dataframe(nrow)
    local df = luajr.list()
    df[0].class = "data.frame"

    -- Make rownames
    local rownames = luajr.integer_r(nullptr)
    rownames._p = nullptr
    rownames._s = internal.CompactRowNames(nrow)
    df[0]["row.names"] = rownames

    return df
end

-- matrix type: specify nrow and ncol
function luajr.matrix(nrow, ncol)
    local m = luajr.numeric_r(nrow * ncol, 0.0)

    -- Make dimensions
    local dim = luajr.integer_r(2)
    dim[1] = nrow
    dim[2] = ncol
    m("dim", dim)

    return m
end

-- datamatrix type: specify nrow, ncol, and column names
function luajr.datamatrix(nrow, ncol, names)
    local m = luajr.matrix(nrow, ncol)

    -- Make column names
    if #names > ncol then error("Supplied more names than columns to luajr.datamatrix.") end
    local colnames = luajr.character_r(ncol)
    for i = 1,#names do colnames[i] = names[i] end
    m("/matrix/colnames", colnames)

    return m
end
