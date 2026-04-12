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


