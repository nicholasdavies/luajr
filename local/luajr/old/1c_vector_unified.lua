----------------------------------
-- X. UNIFIED VECTOR TYPE (v3)  --
----------------------------------

-- Callback-based vector factory. Numeric and character vectors share all method
-- logic; only element-level operations differ, captured in an ops table.
--
-- ops.stype      SEXPTYPE (e.g. R.REALSXP, R.STRSXP)
-- ops.dataptr    function(s) -> data pointer from SEXP
-- ops.null_p     typed nullptr for this pointer type
-- ops.read       function(p, k) -> user-facing value at 1-based index k
-- ops.write      function(self, k, v) write user-facing value at 1-based k
-- ops.write_raw  function(self, k, raw) write raw value (from p[j]) at 1-based k
-- ops.copy       function(dst_s, dst_start, src_p, src_start, count) bulk copy
-- ops.copy_vec   function(dst_s, dst_start, src, count) copy from vectorish
-- ops.fill       function(s, start, count, v) fill with user-facing value
-- ops.is_val     function(b) -> true if b is valid fill/element value for this type

-- Helper: build numeric ops
local numeric_ops = function(ct, r_stype, r_dataptr)
    local vtype = ffi.typeof(ct .. "[?]")
    return {
        stype = r_stype,
        dataptr = r_dataptr,
        null_p = nullptr,
        read = function(p, k) return p[k] end,
        write = function(self, k, v) self.p[k] = v end,
        write_raw = function(self, k, v) self.p[k] = v end,
        copy = function(dst_s, dst_start, src_p, src_start, count)
            local dst_p = r_dataptr(dst_s) - 1
            ffi.copy(dst_p + dst_start, src_p + src_start, sizeof(vtype, count))
        end,
        copy_vec = function(dst_s, dst_start, src, count)
            local dst_p = r_dataptr(dst_s) - 1
            for i = 0, count - 1 do dst_p[dst_start + i] = src[1 + i] end
        end,
        fill = function(s, start, count, v)
            local p = r_dataptr(s) - 1
            for i = start, start + count - 1 do p[i] = v end
        end,
        is_val = function(b) return type(b) == "number" or type(b) == "boolean" end,
    }
end

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

-- Helper: build character ops
local character_ops = {
    stype = R.STRSXP,
    dataptr = R.STRING_PTR,
    null_p = ffi.cast("SEXP*", nullptr),
    read = function(p, k) return from_charsxp(p[k]) end,
    write = function(self, k, v) R.SET_STRING_ELT(self.s, k - 1, to_charsxp(v)) end,
    write_raw = function(self, k, v) R.SET_STRING_ELT(self.s, k - 1, v) end,
    copy = function(dst_s, dst_start, src_p, src_start, count)
        for i = 0, count - 1 do
            R.SET_STRING_ELT(dst_s, dst_start - 1 + i, src_p[src_start + i])
        end
    end,
    copy_vec = function(dst_s, dst_start, src, count)
        for i = 0, count - 1 do
            R.SET_STRING_ELT(dst_s, dst_start - 1 + i, to_charsxp(src[1 + i]))
        end
    end,
    fill = function(s, start, count, v)
        local ch = to_charsxp(v)
        for i = 0, count - 1 do R.SET_STRING_ELT(s, start - 1 + i, ch) end
    end,
    is_val = function(b) return type(b) == "string" or b == luajr.NA_character_ end,
}


-- Shared metatable factory
local mt_vector = function(ops)

    -- Throw an error on an illegal use of a 'byref' vector
    local byref_error = function(method)
        error("cannot call " .. method .. " on a vector passed by reference")
    end

    -- Helper function to (re)allocate memory
    -- self is the current vector
    -- new_c is the new capacity
    -- init is optional callback function(new_s, new_p) to initialize the new memory;
    --   at the time init runs, self.p/self.s still reference old data
    local allocate = function(self, new_c, init)
        if self.c == byref then
            byref_error("reallocate")
        end

        -- allocate new memory (with array indexing starting at 1)
        local new_s = R.allocVector(ops.stype, new_c) -- throws if couldn't allocate
        R.PreserveObject(new_s)
        local new_p = ops.dataptr(new_s) - 1

        -- copy attributes
        -- NOTE This copies all attributes except names, dim, dimnames. There's no
        -- easy way to know the "right" way of extending these (consider insertion
        -- in the middle, or growing a matrix) so let other methods handle them.
        R.copyMostAttrib(self.s, new_s)

        -- initialize
        if init then init(new_s, new_p) end

        -- release current sexp
        if self.p ~= ops.null_p and self.c >= 0 then
            R.ReleaseObject(self.s)
        end

        self.p = new_p
        self.s = new_s
        self.c = new_c
        -- NOTE: caller sets self.n
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
            elseif type(a) == "number" and (ops.is_val(b) or b == nil) then
                -- a copies of b
                if a < 0 then error("assign: count must be non-negative", 2) end
                if self.c == byref and a ~= self.n then byref_error("assign") end
                if self.c == byref or a <= self.c then
                    if b ~= nil then ops.fill(self.s, 1, a, b) end
                    self.n = a
                else
                    allocate(self, a, b ~= nil and function(new_s)
                        ops.fill(new_s, 1, a, b)
                    end)
                    self.n = a
                end
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                if self.c == byref and a.n ~= self.n then byref_error("assign") end
                if self.c == byref or a.n <= self.c then
                    ops.copy(self.s, 1, a.p, 1, a.n)
                    self.n = a.n
                else
                    allocate(self, a.n, function(new_s)
                        ops.copy(new_s, 1, a.p, 1, a.n)
                    end)
                    self.n = a.n
                end
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                if self.c == byref and #a ~= self.n then byref_error("assign") end
                if self.c == byref or #a <= self.c then
                    ops.copy_vec(self.s, 1, a, #a)
                    self.n = #a
                else
                    allocate(self, #a, function(new_s)
                        ops.copy_vec(new_s, 1, a, #a)
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
                allocate(self, n, function(new_s)
                    ops.copy(new_s, 1, self.p, 1, self.n)
                end)
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
                allocate(self, self.n, function(new_s)
                    ops.copy(new_s, 1, self.p, 1, self.n)
                end)
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
                        allocate(self, n, function(new_s)
                            ops.copy(new_s, 1, self.p, 1, self.n)
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
                allocate(self, math.max(1, self.n * 2), function(new_s)
                    ops.copy(new_s, 1, self.p, 1, self.n)
                end)
            elseif self.c < self.n + 1 then
                -- If no capacity, reallocate double the space (min. 1)
                allocate(self, math.max(1, self.c * 2), function(new_s)
                    ops.copy(new_s, 1, self.p, 1, self.n)
                end)
            end
            self.n = self.n + 1
            ops.write(self, self.n, value)
        end,

        pop_back = function(self)
            -- NB. C++ std::vector pop_back on empty vector undefined; here a no-op
            if self.c == byref then byref_error("pop_back") end
            if self.n > 0 then
                if self.c == alias then
                    allocate(self, self.n - 1, function(new_s)
                        ops.copy(new_s, 1, self.p, 1, self.n - 1)
                    end)
                    self.n = self.n - 1
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
            if type(a) == "number" and ops.is_val(b) then
                -- a copies of b
                if a < 0 then error("insert: count must be non-negative", 2) end
                if self.n + a <= self.c then
                    -- In-place shift right
                    for j = self.n, i, -1 do ops.write_raw(self, j + a, self.p[j]) end
                    self.n = self.n + a
                else
                    -- Gapped realloc
                    allocate(self, self.n + a, function(new_s)
                        ops.copy(new_s, 1, self.p, 1, i - 1)
                        ops.copy(new_s, i + a, self.p, i, self.n - i + 1)
                    end)
                    self.n = self.n + a
                end
                -- Fill gap
                ops.fill(self.s, i, a, b)
            elseif ffi.istype(self, a) and b == nil then
                -- from vector
                local na = #a
                if self.n + na <= self.c then
                    for j = self.n, i, -1 do ops.write_raw(self, j + na, self.p[j]) end
                    self.n = self.n + na
                else
                    allocate(self, self.n + na, function(new_s)
                        ops.copy(new_s, 1, self.p, 1, i - 1)
                        ops.copy(new_s, i + na, self.p, i, self.n - i + 1)
                    end)
                    self.n = self.n + na
                end
                -- Fill gap from source vector
                ops.copy(self.s, i, a.p, 1, na)
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                local na = #a
                if self.n + na <= self.c then
                    for j = self.n, i, -1 do ops.write_raw(self, j + na, self.p[j]) end
                    self.n = self.n + na
                else
                    allocate(self, self.n + na, function(new_s)
                        ops.copy(new_s, 1, self.p, 1, i - 1)
                        ops.copy(new_s, i + na, self.p, i, self.n - i + 1)
                    end)
                    self.n = self.n + na
                end
                -- Fill gap from vectorish
                ops.copy_vec(self.s, i, a, na)
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
                allocate(self, self.n - ndel, function(new_s)
                    ops.copy(new_s, 1, self.p, 1, first - 1)
                    ops.copy(new_s, first, self.p, last + 1, self.n - last)
                end)
                self.n = self.n - ndel
            else
                for j = first, self.n - ndel do
                    ops.write_raw(self, j, self.p[j + ndel])
                end
                self.n = self.n - ndel
            end
        end
    }

    -- The metatable
    local mt = {
        __new = function(ctype, a, b)
            local self = ffi.new(ctype)
            self.p = ops.null_p
            self.s = R.NilValue
            if ffi.istype(R.sexp, a) and type(b) == "number" and (b == byref or b == alias) then
                -- reference or alias
                self.p = ops.dataptr(a) - 1
                self.s = a
                self.c = b
                self.n = R.length(a)
            elseif a == nil and b == nil then
                -- empty vector
                allocate(self, 0)
                self.n = 0
            elseif type(a) == "number" and (ops.is_val(b) or b == nil) then
                -- a copies of b
                if a < 0 then error("cannot construct vector with negative size", 2) end
                allocate(self, a, b ~= nil and function(new_s)
                    ops.fill(new_s, 1, a, b)
                end)
                self.n = a
            elseif ffi.istype(ctype, a) and b == nil then
                -- from vector to copy
                allocate(self, a.n, function(new_s)
                    ops.copy(new_s, 1, a.p, 1, a.n)
                end)
                self.n = a.n
            elseif vectorish(a) and b == nil then
                -- from vector-ish object
                allocate(self, #a, function(new_s)
                    ops.copy_vec(new_s, 1, a, #a)
                end)
                self.n = #a
            else
                error("cannot construct vector with argument types " ..
                    type(a) .. ", " .. type(b) .. ".", 2)
            end
            return self
        end,

        __gc = function(self)
            if self.p ~= ops.null_p and self.c >= 0 then
                R.ReleaseObject(self.s)
            end
        end,

        __len = function(self)
            return self.n
        end,

        __index = function(self, k)
            if type(k) == "number" then
                return ops.read(self.p, k)
            else
                return methods[k]
            end
        end,

        __newindex = function(self, k, v)
            ops.write(self, k, v)
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
luajr.logical3   = ffi.metatype("logical3_t",   mt_vector(numeric_ops("int",    R.LGLSXP,  R.LOGICAL)))
luajr.integer3   = ffi.metatype("integer3_t",   mt_vector(numeric_ops("int",    R.INTSXP,  R.INTEGER)))
luajr.numeric3   = ffi.metatype("numeric3_t",   mt_vector(numeric_ops("double", R.REALSXP, R.REAL)))
luajr.character3 = ffi.metatype("character3_t",  mt_vector(character_ops))

-- Vector type checkers
luajr.is_logical3   = function(obj) return ffi.istype(luajr.logical3, obj) end
luajr.is_integer3   = function(obj) return ffi.istype(luajr.integer3, obj) end
luajr.is_numeric3   = function(obj) return ffi.istype(luajr.numeric3, obj) end
luajr.is_character3 = function(obj) return ffi.istype(luajr.character3, obj) end
