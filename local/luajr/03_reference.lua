------------------------
-- 3. REFERENCE TYPES --
------------------------

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
        if init1 == hidden then
            -- do nothing
        elseif type(init1) == "number" then
            if init2 == nil then
                internal.AllocCharacter(self, init1)
            elseif init2 == luajr.NA_character_ then
                internal.AllocCharacterNA(self, init1)
            else
                internal.AllocCharacterTo(self, init1, init2)
            end
        elseif vectorish(init1) then
            internal.AllocCharacter(self, #init1)
            for i = 1,#self do self[i] = init1[i] end
        else
            error("Reference type must be initialised.")
        end
        return self
    end,

    __gc = function(x)
        internal.Release(x._s)
    end,

    __len = function(x)
        return internal.SEXP_length(x._s)
    end,

    __index = function(x, k)
        local v = internal.GetCharacterElt(x._s, k - 1)
        if v == nullptr then
            return luajr.NA_character_
        else
            return ffi.string(v)
        end
    end,

    __newindex = function(x, k, v)
        if v == luajr.NA_character_ then
            internal.SetCharacterElt(x._s, k - 1, nullptr)
        else
            internal.SetCharacterElt(x._s, k - 1, v)
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
luajr.logical_r   = ffi.metatype("logical_rt", mt_basic_r(internal.AllocLogical))
luajr.integer_r   = ffi.metatype("integer_rt", mt_basic_r(internal.AllocInteger))
luajr.numeric_r   = ffi.metatype("numeric_rt", mt_basic_r(internal.AllocNumeric))
luajr.character_r = ffi.metatype("character_rt", mt_character_r)

-- Reference type checkers
luajr.is_logical_r   = function(obj) return ffi.istype(luajr.logical_r, obj) end
luajr.is_integer_r   = function(obj) return ffi.istype(luajr.integer_r, obj) end
luajr.is_numeric_r   = function(obj) return ffi.istype(luajr.numeric_r, obj) end
luajr.is_character_r = function(obj) return ffi.istype(luajr.character_r, obj) end


