------------------------------
-- X. CHARACTER VECTOR TYPE --
------------------------------

-- Character vector uses SEXP* p (via STRING_PTR) for element access.
-- Elements are CHARSXP SEXPs; user-facing API works with Lua strings and
-- luajr.NA_character_ for NA values.
-- This is a separate implementation from the numeric vector types because:
-- - Element access goes through STRING_ELT/SET_STRING_ELT, not pointer indexing
-- - Cannot use ffi.copy for bulk operations (SET_STRING_ELT updates ref counts)
-- - Reads return Lua strings (via CHAR + ffi.string), writes accept Lua strings
--   (via mkChar)

-- Helper: convert Lua string or NA to CHARSXP for writing
local to_charsxp = function(v)
    if v == luajr.NA_character_ then
        return luajr.NA_character_
    else
        return R.mkChar(v)
    end
end

-- Helper: convert CHARSXP to Lua string or NA for reading
local from_charsxp = function(v)
    if v == luajr.NA_character_ then
        return luajr.NA_character_
    else
        return ffi.string(R.CHAR(v))
    end
end

-- Metatable for character vector type
-- typedef struct { SEXP* p; SEXP s; double n; double c; } character_t;
local mt_character_vector = function()
    local stype = R.STRSXP

    -- Throw an error on an illegal use of a 'byref' vector
    local byref_error = function(method)
        error("cannot call " .. method .. " on a vector passed by reference")
    end

    -- Helper to copy elements between STRSXP SEXPs via SET_STRING_ELT.
    -- Cannot use ffi.copy/memcpy because SET_STRING_ELT updates reference counts.
    local copy_elts = function(dst_s, dst_off, src_p, src_off, count)
        for i = 0, count - 1 do
            R.SET_STRING_ELT(dst_s, dst_off + i, src_p[src_off + i + 1])
        end
    end

    -- Helper function to (re)allocate memory
    -- self is the current vector
    -- new_c is the new capacity
    -- init is optional callback function(new_s, new_p) to initialize the new memory
    local allocate = function(self, new_c, init)
        -- ensure not a byref
        if self.c == byref then
            byref_error("reallocate")
        end

        -- allocate new memory
        local new_s = R.allocVector(stype, new_c) -- throws if couldn't allocate
        R.PreserveObject(new_s)
        local new_p = R.STRING_PTR(new_s) - 1

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
        if init then
            init(new_s, new_p)
        end

        -- release current sexp
        if self.p ~= ffi.cast("SEXP*", nullptr) and self.c >= 0 then
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
            elseif type(a) == "number" and (type(b) == "string" or b == luajr.NA_character_ or b == nil) then
                -- a copies of b
                if a < 0 then error("assign: count must be non-negative", 2) end
                if self.c == byref and a ~= self.n then byref_error("assign") end
                if self.c == byref or a <= self.c then
                    if b ~= nil then
                        local ch = to_charsxp(b)
                        for i = 0, a - 1 do R.SET_STRING_ELT(self.s, i, ch) end
                    end
                    self.n = a
                else
                    local ch = b ~= nil and to_charsxp(b) or nil
                    allocate(self, a, ch and function(new_s)
                        for i = 0, a - 1 do R.SET_STRING_ELT(new_s, i, ch) end
                    end)
                    self.n = a
                end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if self.c == byref and a.n ~= self.n then byref_error("assign") end
                if self.c == byref or a.n <= self.c then
                    copy_elts(self.s, 0, a.p, 0, a.n)
                    self.n = a.n
                else
                    allocate(self, a.n, function(new_s)
                        copy_elts(new_s, 0, a.p, 0, a.n)
                    end)
                    self.n = a.n
                end
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                if self.c == byref and #a ~= self.n then byref_error("assign") end
                if self.c == byref or #a <= self.c then
                    for i = 1, #a do R.SET_STRING_ELT(self.s, i - 1, to_charsxp(a[i])) end
                    self.n = #a
                else
                    allocate(self, #a, function(new_s)
                        for i = 1, #a do R.SET_STRING_ELT(new_s, i - 1, to_charsxp(a[i])) end
                    end)
                    self.n = #a
                end
            else
                error("cannot use vector:assign with argument types " ..
                    type(a) .. ", " .. type(b) .. ".", 2)
            end
        end,

        print = function(self)
            for k, v in pairs(self) do
                print(k, v)
            end
        end,

        concat = function(self, sep)
            sep = sep or ","
            local str = ""
            for i = 1, #self do
                local v = from_charsxp(self.p[i])
                if v == luajr.NA_character_ then v = "NA" end
                if i ~= #self then
                    str = str .. v .. sep
                else
                    str = str .. v
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
                local old_s, old_n = self.s, self.n
                allocate(self, n, function(new_s)
                    copy_elts(new_s, 0, R.STRING_PTR(old_s) - 1, 0, old_n)
                end)
                self.n = old_n
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
                local old_s, old_n = self.s, self.n
                allocate(self, old_n, function(new_s)
                    copy_elts(new_s, 0, R.STRING_PTR(old_s) - 1, 0, old_n)
                end)
                self.n = old_n
            end
        end,

        -- Modify
        clear = function(self)
            if self.c == byref then
                byref_error("clear")
            elseif self.c == alias then
                allocate(self, 0)
                self.n = 0
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
                    if n > self.c or self.c < 0 then
                        local old_s, old_n = self.s, self.n
                        allocate(self, n, function(new_s)
                            copy_elts(new_s, 0, R.STRING_PTR(old_s) - 1, 0, old_n)
                        end)
                    end
                    self.n = n
                end
            end
        end,

        push_back = function(self, value)
            if value == nil then error("push_back: value must not be nil", 2) end
            if self.c == byref then byref_error("push_back") end
            if self.c == alias then
                local old_s, old_n = self.s, self.n
                allocate(self, math.max(1, old_n * 2), function(new_s)
                    copy_elts(new_s, 0, R.STRING_PTR(old_s) - 1, 0, old_n)
                end)
                self.n = old_n
            elseif self.c < self.n + 1 then
                -- If no capacity, reallocate double the space (min. 1)
                local old_s, old_n = self.s, self.n
                allocate(self, math.max(1, self.c * 2), function(new_s)
                    copy_elts(new_s, 0, R.STRING_PTR(old_s) - 1, 0, old_n)
                end)
                self.n = old_n
            end
            self.n = self.n + 1
            R.SET_STRING_ELT(self.s, self.n - 1, to_charsxp(value))
        end,

        pop_back = function(self)
            -- NB. C++ std::vector pop_back on empty vector undefined; here a no-op
            if self.c == byref then byref_error("pop_back") end
            if self.n > 0 then
                if self.c == alias then
                    local old_s, old_n = self.s, self.n
                    allocate(self, old_n - 1, function(new_s)
                        copy_elts(new_s, 0, R.STRING_PTR(old_s) - 1, 0, old_n - 1)
                    end)
                    self.n = old_n - 1
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
            if type(a) == "number" and (type(b) == "string" or b == luajr.NA_character_) then
                -- a copies of b
                if a < 0 then error("insert: count must be non-negative", 2) end
                local ch = to_charsxp(b)
                if self.n + a <= self.c then
                    -- Shift tail right
                    for j = self.n - 1, i - 1, -1 do
                        R.SET_STRING_ELT(self.s, j + a, self.p[j + 1])
                    end
                    self.n = self.n + a
                else
                    local old_p, old_n = self.p, self.n
                    allocate(self, old_n + a, function(new_s)
                        copy_elts(new_s, 0, old_p, 0, i - 1)
                        copy_elts(new_s, i - 1 + a, old_p, i - 1, old_n - i + 1)
                    end)
                    self.n = old_n + a
                end
                -- Fill gap
                for j = 0, a - 1 do R.SET_STRING_ELT(self.s, i - 1 + j, ch) end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                local na = #a
                if self.n + na <= self.c then
                    for j = self.n - 1, i - 1, -1 do
                        R.SET_STRING_ELT(self.s, j + na, self.p[j + 1])
                    end
                    self.n = self.n + na
                else
                    local old_p, old_n = self.p, self.n
                    allocate(self, old_n + na, function(new_s)
                        copy_elts(new_s, 0, old_p, 0, i - 1)
                        copy_elts(new_s, i - 1 + na, old_p, i - 1, old_n - i + 1)
                    end)
                    self.n = old_n + na
                end
                -- Fill gap from source vector
                copy_elts(self.s, i - 1, a.p, 0, na)
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                local na = #a
                if self.n + na <= self.c then
                    for j = self.n - 1, i - 1, -1 do
                        R.SET_STRING_ELT(self.s, j + na, self.p[j + 1])
                    end
                    self.n = self.n + na
                else
                    local old_p, old_n = self.p, self.n
                    allocate(self, old_n + na, function(new_s)
                        copy_elts(new_s, 0, old_p, 0, i - 1)
                        copy_elts(new_s, i - 1 + na, old_p, i - 1, old_n - i + 1)
                    end)
                    self.n = old_n + na
                end
                -- Fill gap from vectorish
                for j = 1, na do R.SET_STRING_ELT(self.s, i - 2 + j, to_charsxp(a[j])) end
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
                local old_p, old_n = self.p, self.n
                allocate(self, old_n - ndel, function(new_s)
                    copy_elts(new_s, 0, old_p, 0, first - 1)
                    copy_elts(new_s, first - 1, old_p, last, old_n - last)
                end)
                self.n = old_n - ndel
            else
                for j = first, self.n - ndel do
                    R.SET_STRING_ELT(self.s, j - 1, self.p[j + ndel])
                end
                self.n = self.n - ndel
            end
        end
    }

    -- The metatable
    local mt = {
        __new = function(ctype, a, b)
            local self = ffi.new(ctype)
            self.p = ffi.cast("SEXP*", nullptr)
            self.s = R.NilValue
            if ffi.istype(R.sexp, a) and type(b) == "number" and (b == byref or b == alias) then
                -- reference or alias
                self.p = R.STRING_PTR(a) - 1
                self.s = a
                self.c = b
                self.n = R.length(a)
            elseif a == nil and b == nil then
                -- empty vector
                allocate(self, 0)
                self.n = 0
            elseif type(a) == "number" and (type(b) == "string" or b == luajr.NA_character_ or b == nil) then
                -- a copies of b
                if a < 0 then error("cannot construct vector with negative size", 2) end
                local ch = b ~= nil and to_charsxp(b) or nil
                allocate(self, a, ch and function(new_s)
                    for i = 0, a - 1 do R.SET_STRING_ELT(new_s, i, ch) end
                end)
                self.n = a
            elseif ffi.istype(ctype, a) and b == nil then
                -- from vector to copy
                allocate(self, a.n, function(new_s)
                    copy_elts(new_s, 0, a.p, 0, a.n)
                end)
                self.n = a.n
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                allocate(self, #a, function(new_s)
                    for i = 1, #a do R.SET_STRING_ELT(new_s, i - 1, to_charsxp(a[i])) end
                end)
                self.n = #a
            else
                error("cannot construct vector with argument types " ..
                    type(a) .. ", " .. type(b) .. ".", 2)
            end
            return self
        end,

        __gc = function(self)
            if self.p ~= ffi.cast("SEXP*", nullptr) and self.c >= 0 then
                R.ReleaseObject(self.s)
            end
        end,

        __len = function(self)
            return self.n
        end,

        __index = function(self, k)
            if type(k) == "number" then
                return from_charsxp(self.p[k])
            else
                return methods[k]
            end
        end,

        __newindex = function(self, k, v)
            R.SET_STRING_ELT(self.s, k - 1, to_charsxp(v))
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

-- Character vector type definition
luajr.character2 = ffi.metatype("character_t", mt_character_vector())

-- Character vector type checker
luajr.is_character2 = function(obj) return ffi.istype(luajr.character2, obj) end
