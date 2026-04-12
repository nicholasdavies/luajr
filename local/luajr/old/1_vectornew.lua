------------------------
-- X. NEW VECTOR TYPE --
------------------------

-- Vector capacity flags
-- TODO document
local byref = -1
local alias = -2


-- Metatable for vector type
-- typedef struct { ctype* p; SEXP s; double n; double c; } [vector]_t;
local mt_vector = function(ct, stype, dataptr)
    local vtype = ffi.typeof(ct .. "[?]")
    local ptype = ffi.typeof(ct .. "*")

    -- Throw an error on an illegal use of a 'byref' vector
    local byref_error = function(method)
        error("cannot call ", method, " on a vector passed by reference")
    end

    -- Helper function to set vector memory
    -- params = { n }: n elements but don't set
    -- params = { fill, n }: n copies of val
    -- params = { p, n }: n elements from p + 1
    -- params = { copy, n }: elements from copy[i], i = 1 to n
    -- params = { insert, insert_n, outer_p, outer_n }: outer_n elements from outer_p + 1, leaving gap of insert_n at insert
    -- returns number of elements written
    local set = function(p, params)
        if params.fill ~= nil then
            for i = 1, params.n do p[i] = params.fill end
        elseif params.p ~= nil then
            ffi.copy(p + 1, params.p + 1, sizeof(vtype, params.n))
        elseif params.copy ~= nil then
            for i = 1, params.n do p[i] = params.copy[i] end
        elseif params.insert ~= nil then
            ffi.copy(p + 1, params.outer_p + 1, sizeof(vtype, params.insert - 1))
            ffi.copy(p + params.insert + params.insert_n,
                params.outer_p + params.insert,
                sizeof(vtype, params.outer_n - params.insert + 1))
            return params.insert_n + params.outer_n
        elseif params.erase ~= nil then
            ffi.copy(p + 1, params.outer_p + 1, sizeof(vtype, params.erase - 1))
            ffi.copy(p + params.erase,
                params.outer_p + params.erase_last + 1,
                sizeof(vtype, params.outer_n - params.erase_last))
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
        self.n = set(new_p, set_params)

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
            elseif type(a) == "number" and (type(b) == "number" or type(b) == "boolean" or b == nil) then
                -- a copies of b
                if a < 0 then error("assign: count must be non-negative", 2) end
                if self.c == byref and a ~= self.n then byref_error("assign") end
                if self.c == byref or a <= self.c then
                    self.n = set(self.p, { fill = b, n = a })
                else
                    allocate(self, a, { fill = b, n = a })
                end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if self.c == byref and a.n ~= self.n then byref_error("assign") end
                if self.c == byref or a.n <= self.c then
                    self.n = set(self.p, { p = a.p, n = a.n })
                else
                    allocate(self, a.n, { p = a.p, n = a.n })
                end
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                if self.c == byref and #a ~= self.n then byref_error("assign") end
                if self.c == byref or #a <= self.c then
                    self.n = set(self.p, { copy = a, n = #a })
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
                    else
                        self.n = n
                    end
                end
            end
        end,

        push_back = function(self, value)
            if value == nil then error("push_back: value must not be nil", 2) end
            if self.c == byref then byref_error("push_back") end
            if self.c == alias then
                allocate(self, math.max(1, self.n * 2), { p = self.p, n = self.n })
            elseif self.c < self.n + 1 then
                -- If no capacity, reallocate double the space (min. 1)
                allocate(self, math.max(1, self.c * 2), { p = self.p, n = self.n })
            end
            self.n = self.n + 1
            self.p[self.n] = value
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
            if type(a) == "number" and type(b) == "number" then
                -- a copies of b
                if a < 0 then error("insert: count must be non-negative", 2) end
                if self.n + a <= self.c then
                    for j = self.n,i,-1 do self.p[j + a] = self.p[j] end
                    self.n = self.n + a
                else
                    allocate(self, self.n + a, { insert = i, insert_n = a, outer_p = self.p, outer_n = self.n })
                end
                for j = i,i+a-1 do self.p[j] = b end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if self.n + #a <= self.c then
                    for j = self.n,i,-1 do self.p[j + #a] = self.p[j] end
                    self.n = self.n + #a
                else
                    allocate(self, self.n + #a, { insert = i, insert_n = #a, outer_p = self.p, outer_n = self.n })
                end
                ffi.copy(self.p + i, a.p + 1, sizeof(vtype, #a))
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                if self.n + #a <= self.c then
                    for j = self.n,i,-1 do self.p[j + #a] = self.p[j] end
                    self.n = self.n + #a
                else
                    allocate(self, self.n + #a, { insert = i, insert_n = #a, outer_p = self.p, outer_n = self.n })
                end
                for j = 1,#a do self.p[j + i - 1] = a[j] end
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
                for i = first, self.n - ndel do self.p[i] = self.p[i + ndel] end
                self.n = self.n - ndel
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
            elseif type(a) == "number" and (type(b) == "number" or type(b) == "boolean" or b == nil) then
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
                return self.p[k]
            else
                return methods[k]
            end
        end,

        __newindex = function(self, k, v)
            if self.c == alias then
                allocate(self, self.n, { p = self.p, n = self.n })
            end
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

-- Vector type definitions
luajr.logical2 = ffi.metatype("logical_t", mt_vector("int",    R.LGLSXP,  R.LOGICAL))
luajr.integer2 = ffi.metatype("integer_t", mt_vector("int",    R.INTSXP,  R.INTEGER))
luajr.numeric2 = ffi.metatype("numeric_t", mt_vector("double", R.REALSXP, R.REAL))

-- Vector type checkers
luajr.is_logical2 = function(obj) return ffi.istype(luajr.logical2, obj) end
luajr.is_integer2 = function(obj) return ffi.istype(luajr.integer2, obj) end
luajr.is_numeric2 = function(obj) return ffi.istype(luajr.numeric2, obj) end


