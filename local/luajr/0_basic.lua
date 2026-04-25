-- luajr module

-- CONTENTS --
-- 0. PRELIMINARIES --
-- 1. INTERNAL API --
-- 2. LUAJR API BASICS --
-- 3. VECTOR TYPES --
-- 4. EXTRA TYPES --
-- 5. PARALLEL --
-- 6. DEBUGGER --



----------------------
-- 0. PRELIMINARIES --
----------------------

-- Load ffi module
local ffi = require("ffi")

-- Load additional convenience functions for tables (provided by LuaJIT)
table.new = require("table.new")
table.clear = require("table.clear")

-- Load R module
local R = require("R")

-- Script receives the path to the luajr R package dylib as argument
local luajr_dylib_path = ({...})[1]

-- Script also receives the path to debugger.lua as argument
local debugger_lua_path = ({...})[2]

-- Null pointer object
local nullptr = ffi.cast("void*", 0)

-- Pointer-to-pointer type for writing pointer values
local voidpp = ffi.typeof("void**")

-- Pointer-to-sexp type for writing SEXP values
local sexpp  = ffi.typeof("SEXP*")

-- "Hidden" sentinel object (unused)
ffi.cdef[[ typedef struct { int a; } HIDDEN_t; ]]
local hidden = ffi.new("HIDDEN_t")



---------------------
-- 1. INTERNAL API --
---------------------

-- 'Internal' API for interfacing with C, R; struct types
ffi.cdef[[
// Forward declarations
struct SEXPREC;
struct lua_State;
typedef struct lua_State lua_State;
typedef struct SEXPREC* SEXP;

// R vector types
typedef struct { int* p;    SEXP s; double n; double c; } logical_t;
typedef struct { int* p;    SEXP s; double n; double c; } integer_t;
typedef struct { double* p; SEXP s; double n; double c; } numeric_t;
typedef struct { SEXP* p;   SEXP s; double n; double c; } character_t;
typedef struct { SEXP* p;   SEXP s; double n; double c; } list_t;

// Other R types
typedef struct { SEXP s; } environment_t;
typedef struct { SEXP s; SEXP cached; } function_t;

// Other luajr types
typedef struct { lua_State** l; int n; } workers_t;

// C functions
void* memcpy(void* dest, const void* src, size_t count);
size_t strlen(const char* str);

// Parallel functionality
int luajr_parallel_ncores();
void luajr_parallel_newworkers(workers_t* w);
void luajr_parallel_closeworkers(workers_t* w);
void luajr_parallel_srun(workers_t* w);
void luajr_parallel_prun(workers_t* w);
void luajr_parallel_pfor(workers_t* w, int i0, int i1);
]]
local internal = ffi.load(luajr_dylib_path)



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
local from_sexp
local to_sexp
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

-- Get nparams and isvararg for a Lua function.
-- Called from C++ (luajr_func_info).
function luajr.get_func_info(f)
    local info = debug.getinfo(f, "u")
    return info.nparams, info.isvararg and 1 or 0
end

-- sizeof helper
-- ffi.sizeof() fails if the calculated size is larger than 2^31-1 bytes.
-- We need a special version of ffi.sizeof() for use with vector types in
-- order to be able to work with larger chunks of memory.
local sizeof = function(vtype, nelem)
    return ffi.sizeof(vtype, 1) * nelem
end


