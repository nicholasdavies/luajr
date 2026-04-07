-- R API for luajr
-- Entries between === markers managed by add_rapi() in luajr/local/add_rapi.R

local ffi = require("ffi")

-- Script receives the R version as argument, e.g. 4.5.3 -> 40503
local R_version = ({...})[1]

-- Declarations
ffi.cdef[[
// SEXP
struct SEXPREC;
typedef struct SEXPREC* SEXP;

// SEXPTYPEs
enum
{
    NILSXP = 0,         // NULL
    SYMSXP = 1,         // symbols
    LISTSXP = 2,        // pairlists
    CLOSXP = 3,         // closures
    ENVSXP = 4,         // environments
    PROMSXP = 5,        // promises
    LANGSXP = 6,        // language objects
    SPECIALSXP = 7,     // special functions
    BUILTINSXP = 8,     // builtin functions
    CHARSXP = 9,        // internal character strings
    LGLSXP = 10,        // logical vectors
    INTSXP = 13,        // integer vectors
    REALSXP = 14,       // numeric vectors
    CPLXSXP = 15,       // complex vectors
    STRSXP = 16,        // character vectors
    DOTSXP = 17,        // dot-dot-dot object
    ANYSXP = 18,        // make “any” args work
    VECSXP = 19,        // list (generic vector)
    EXPRSXP = 20,       // expression vector
    BCODESXP = 21,      // byte code
    EXTPTRSXP = 22,     // external pointer
    WEAKREFSXP = 23,    // weak reference
    RAWSXP = 24,        // raw vector
    OBJSXP = 25         // objects not of simple type
};

// === R API declarations ===
void R_PreserveObject(SEXP);
void R_ReleaseObject(SEXP);
SEXP Rf_protect(SEXP);
void Rf_unprotect(int);
// === end R API declarations ===

ptrdiff_t Rf_xlength(SEXP); // Wrapped manually below to convert to number
]]

-- Resolve symbols from the R shared library (already loaded in process)
local C = ffi.C

-- Module table
local R = {}

-- Make R module available for 'require'
function package.preload.R()
    return R
end

-- === R API bindings ===
R.PreserveObject = C.R_PreserveObject
R.ReleaseObject = C.R_ReleaseObject
R.protect = C.Rf_protect
R.unprotect = C.Rf_unprotect
-- === end R API bindings ===

-- Convert 64-bit length to Lua number
R.length = function(sexp)
    return tonumber(C.Rf_xlength(sexp))
end

-- LuaJIT SEXP type
R.sexp = ffi.typeof("SEXP")

-- R version
R.version = R_version

return R
