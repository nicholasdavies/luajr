local ffi = require('ffi')

ffi.cdef[[
int AllocRDataMatrix(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);
int AllocRDataFrame(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);
]]
local luajr_internal = ffi.load("@luajr_dylib_path@")

local luajr = {}

function luajr.DataMatrix(nrow, ncol, names)
    data = ffi.new("double*[?]", ncol)
    cnames = ffi.new("const char*[?]", ncol, names)
    id = luajr_internal.AllocRDataMatrix(nrow, ncol, cnames, data)
    m = { __robj_ret_i = id }
    for i = 1, #names do
        m[names[i]] = data[i-1]
    end
    return m
end

function luajr.DataFrame(nrow, ncol, names)
    data = ffi.new("double*[?]", ncol)
    cnames = ffi.new("const char*[?]", ncol, names)
    id = luajr_internal.AllocRDataFrame(nrow, ncol, cnames, data)
    df = { __robj_ret_i = id }
    for i = 1, #names do
        df[names[i]] = data[i-1]
    end
    return df
end

package.preload.luajr = function() return luajr end
