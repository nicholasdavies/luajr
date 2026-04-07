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


