-------------------------
-- 2. LUAJR API BASICS --
-------------------------

-- Create luajr module table
local luajr = {}

-- Make luajr module available for 'require'
function package.preload.luajr()
    return luajr
end

-- TRUE, FALSE, NA, NULL definitions
luajr.TRUE          = 1
luajr.FALSE         = 0
luajr.NA_logical_   = R.NA_LOGICAL
luajr.NA_integer_   = R.NA_INTEGER
luajr.NA_real_      = R.NA_REAL
luajr.NA_character_ = R.NA_STRING
luajr.NULL          = R.NilValue

-- Forward declarations
local sexp_get_attr
local sexp_set_attr
local vectorish

-- Buffer for luajr.readline
local buf = nil

-- Readline utility
function luajr.readline(prompt)
    if buf == nil then
        buf = ffi.new("unsigned char[1024]")
    end

    R.FlushConsole()
    R.ReadConsole(prompt or "", buf, 1024, 0)

    -- remove terminating newline, but guard against 0-length string
    local len = ffi.C.strlen(buf)
    return ffi.string(buf, len == 0 and 0 or len - 1)
end

-- Malloc and sizeof helpers
-- ffi.sizeof() fails if the calculated size is larger than 2^31-1 bytes,
-- as does ffi.new() (see lj_ctype_vlsize in lj_ctype.c). We use malloc
-- directly for vector allocations, so the limit on ffi.new() does not restrict
-- the size of allocated vector types. But we need a special version of
-- ffi.sizeof() for use with vector types in order to be able to work with
-- larger chunks of memory. We also use a wrapper around ffi.C.malloc() to
-- limit allocation size to 128 GiB, which can be overwritten by changing
-- luajr.max_alloc below.
luajr.max_alloc = 2^37

local malloc = function(size)
    if (size > luajr.max_alloc) then
        error(string.format("Cannot allocate a block larger than " ..
            luajr.max_alloc / 1024^3 .. " GiB. Requested size: " ..
            size / 1024^3 .. " GiB."))
    end
    return ffi.C.malloc(size)
end

local sizeof = function(vtype, nelem)
    return ffi.sizeof(vtype, 1) * nelem
end


