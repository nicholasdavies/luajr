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


