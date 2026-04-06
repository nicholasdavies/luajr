-- R API for luajr
-- Do not hand edit. Add new entries with add_rapi() in luajr/local/add_rapi.R

local ffi = require("ffi")

-- Declarations
ffi.cdef[[
// === R API declarations ===
void R_FlushConsole(void);
int R_ReadConsole(const char* prompt, unsigned char* buf, int buflen, int hist);
]]

-- Resolve symbols from the R shared library (already loaded in process)
local C = ffi.C

-- Module table
local R = {}

-- === R API bindings ===
R.R_FlushConsole = C.R_FlushConsole
R.R_ReadConsole = C.R_ReadConsole

return R
