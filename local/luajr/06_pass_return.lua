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
    [internal.LOGICAL_V]   = function(x, s) ffi.C.memcpy(x.p + 1, R.LOGICAL(s), ffi.sizeof("int") * R.length(s)) end,
    [internal.INTEGER_V]   = function(x, s) ffi.C.memcpy(x.p + 1, R.INTEGER(s), ffi.sizeof("int") * R.length(s)) end,
    [internal.NUMERIC_V]   = function(x, s) ffi.C.memcpy(x.p + 1, R.REAL(s), ffi.sizeof("double") * R.length(s)) end
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


