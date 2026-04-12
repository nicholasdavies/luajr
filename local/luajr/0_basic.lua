-- luajr module

-- CONTENTS --
-- 0. PRELIMINARIES --
-- 1. INTERNAL API --
-- 2. LUAJR API BASICS --
-- 3. VECTOR TYPES --
-- 4. LIST TYPE --
-- 5. PASS TO / RETURN FROM LUA --
-- 6. EXTRA TYPES --
-- 7. DEBUGGER --



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
typedef struct SEXPREC* SEXP;

// Type codes
// See also: ./src/shared.h
enum
{
    // TODO xfer to use R.* types
    NULL_T = 0, //NILSXP,
    LIST_T = 19, //VECSXP,

    LOGICAL_T = 10, //LGLSXP,
    INTEGER_T = 13, //INTSXP,
    NUMERIC_T = 14, //REALSXP,
    CHARACTER_T = 16, //STRSXP,

    SEXP_T = 63, // Generic SEXP
    REFERENCE_T = 64,
    VECTOR_T = 128,

    LOGICAL_R =   LOGICAL_T   | REFERENCE_T,
    INTEGER_R =   INTEGER_T   | REFERENCE_T,
    NUMERIC_R =   NUMERIC_T   | REFERENCE_T,
    CHARACTER_R = CHARACTER_T | REFERENCE_T,
    LOGICAL_V =   LOGICAL_T   | VECTOR_T,
    INTEGER_V =   INTEGER_T   | VECTOR_T,
    NUMERIC_V =   NUMERIC_T   | VECTOR_T,
    CHARACTER_V = CHARACTER_T | VECTOR_T,
};

// Vector types
typedef struct { int* p;    SEXP s; double n; double c; } logical_t;
typedef struct { int* p;    SEXP s; double n; double c; } integer_t;
typedef struct { double* p; SEXP s; double n; double c; } numeric_t;
typedef struct { SEXP* p;   SEXP s; double n; double c; } character_t;

// C functions
void* memcpy(void* dest, const void* src, size_t count);
size_t strlen(const char* str);
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

-- sizeof helper
-- ffi.sizeof() fails if the calculated size is larger than 2^31-1 bytes.
-- We need a special version of ffi.sizeof() for use with vector types in
-- order to be able to work with larger chunks of memory.
local sizeof = function(vtype, nelem)
    return ffi.sizeof(vtype, 1) * nelem
end


