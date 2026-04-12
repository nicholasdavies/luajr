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

-- Copies a luajr object to allocated memory so that it can be taken in by R.
--   obj is the luajr object;
--   ptr is a SEXP* (_pointer_ to SEXP) if obj is a vector or reference type;
--     or a SEXP if obj is a bare SEXP.
function luajr.return_copy(obj, ptr)
    if luajr.is_logical(obj) or luajr.is_integer(obj) or
       luajr.is_numeric(obj) or luajr.is_character(obj) then
        obj:shrink_to_fit()
        ffi.cast(voidpp, ptr)[0] = obj.s
    elseif ffi.istype(R.sexp, obj) then
        ffi.cast(voidpp, ptr)[0] = obj
    else
        error("luajr.return_copy should not be called with an object of this type.")
    end
end


