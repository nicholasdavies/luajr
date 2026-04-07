-- luajr module

-- CONTENTS --
-- 0. PRELIMINARIES --
-- 1. INTERNAL API --
-- 2. LUAJR API BASICS --
-- 3. REFERENCE TYPES --
-- 4. VECTOR TYPES --
-- 5. LIST TYPE --
-- 6. PASS TO / RETURN FROM LUA --
-- 7. EXTRA TYPES --
-- 8. DEBUGGER --


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

-- "Hidden" sentinel object for internal use
ffi.cdef[[ typedef struct { int a; } HIDDEN_t; ]]
local hidden = ffi.new("HIDDEN_t")


