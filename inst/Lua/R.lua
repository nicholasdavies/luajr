-- R API for luajr
-- Entries between === markers managed by add_rapi() in luajr/local/add_rapi.R

local ffi = require("ffi")

-- Script receives the R version as argument, e.g. 4.5.3 -> 40503
local R_version = ({...})[1]

-- Script also receives the path to the luajr R package dylib as argument
local luajr_dylib_path = ({...})[2]

-- Declarations
ffi.cdef[[
// SEXP
struct SEXPREC;
typedef struct SEXPREC* SEXP;
typedef ptrdiff_t R_xlen_t;
typedef unsigned int SEXPTYPE;

// === R API declarations ===
int *INTEGER(SEXP x);
int *LOGICAL(SEXP x);
const char *R_CHAR(SEXP x);
void R_FlushConsole(void);
void R_PreserveObject(SEXP);
int R_ReadConsole(const char* prompt, unsigned char* buf, int buflen, int hist);
void R_ReleaseObject(SEXP);
double *REAL(SEXP x);
SEXP Rf_allocVector(SEXPTYPE, R_xlen_t);
SEXP Rf_dimnamesgets(SEXP, SEXP);
SEXP Rf_getAttrib(SEXP, SEXP);
SEXP Rf_install(const char *);
SEXP Rf_mkChar(const char *);
SEXP Rf_protect(SEXP);
SEXP Rf_setAttrib(SEXP, SEXP, SEXP);
const char * Rf_type2char(SEXPTYPE);
void Rf_unprotect(int);
void SET_STRING_ELT(SEXP x, R_xlen_t i, SEXP v);
SEXP SET_VECTOR_ELT(SEXP x, R_xlen_t i, SEXP v);
SEXP STRING_ELT(SEXP x, R_xlen_t i);
int TYPEOF(SEXP x);
// === end R API declarations ===

R_xlen_t Rf_xlength(SEXP); // Wrapped manually below to convert to number

// R constants -- bound manually below
extern SEXP R_NilValue;
extern SEXP R_UnboundValue;
extern SEXP R_MissingArg;
extern SEXP R_GlobalEnv;
extern SEXP R_EmptyEnv;
extern SEXP R_BaseEnv;
extern SEXP R_NaString;
extern SEXP R_BlankString;
extern SEXP R_NamesSymbol;
extern SEXP R_ClassSymbol;
extern SEXP R_DimSymbol;
extern SEXP R_DimNamesSymbol;
extern SEXP R_RowNamesSymbol;
extern double R_NaReal;
extern int R_NaInt;
]]

-- Resolve symbols via the luajr dylib (which links against R)
local C = ffi.load(luajr_dylib_path)

-- Module table
local R = {
    -- SEXPTYPEs
    NILSXP = 0,         -- NULL
    SYMSXP = 1,         -- symbols
    LISTSXP = 2,        -- pairlists
    CLOSXP = 3,         -- closures
    ENVSXP = 4,         -- environments
    PROMSXP = 5,        -- promises
    LANGSXP = 6,        -- language objects
    SPECIALSXP = 7,     -- special functions
    BUILTINSXP = 8,     -- builtin functions
    CHARSXP = 9,        -- internal character strings
    LGLSXP = 10,        -- logical vectors
    INTSXP = 13,        -- integer vectors
    REALSXP = 14,       -- numeric vectors
    CPLXSXP = 15,       -- complex vectors
    STRSXP = 16,        -- character vectors
    DOTSXP = 17,        -- dot-dot-dot object
    ANYSXP = 18,        -- make “any” args work
    VECSXP = 19,        -- list (generic vector)
    EXPRSXP = 20,       -- expression vector
    BCODESXP = 21,      -- byte code
    EXTPTRSXP = 22,     -- external pointer
    WEAKREFSXP = 23,    -- weak reference
    RAWSXP = 24,        -- raw vector
    OBJSXP = 25         -- objects not of simple type
}

-- Make R module available for 'require'
function package.preload.R()
    return R
end

-- === R API bindings ===
R.allocVector = C.Rf_allocVector
R.CHAR = C.R_CHAR
R.dimnamesgets = C.Rf_dimnamesgets
R.FlushConsole = C.R_FlushConsole
R.getAttrib = C.Rf_getAttrib
R.install = C.Rf_install
R.INTEGER = C.INTEGER
R.LOGICAL = C.LOGICAL
R.mkChar = C.Rf_mkChar
R.PreserveObject = C.R_PreserveObject
R.PROTECT = C.Rf_protect
R.ReadConsole = C.R_ReadConsole
R.REAL = C.REAL
R.ReleaseObject = C.R_ReleaseObject
R.SET_STRING_ELT = C.SET_STRING_ELT
R.SET_VECTOR_ELT = C.SET_VECTOR_ELT
R.setAttrib = C.Rf_setAttrib
R.STRING_ELT = C.STRING_ELT
R.type2char = C.Rf_type2char
R.TYPEOF = C.TYPEOF
R.UNPROTECT = C.Rf_unprotect
-- === end R API bindings ===

-- Convert 64-bit length to Lua number
R.length = function(sexp)
    return tonumber(C.Rf_xlength(sexp))
end

-- SEXP type name as string
R.typename = function(sexp)
    return ffi.string(C.Rf_type2char(C.TYPEOF(sexp)))
end

-- R constants
R.NilValue = C.R_NilValue
R.UnboundValue = C.R_UnboundValue
R.MissingArg = C.R_MissingArg
R.GlobalEnv = C.R_GlobalEnv
R.EmptyEnv = C.R_EmptyEnv
R.BaseEnv = C.R_BaseEnv
R.BlankString = C.R_BlankString
R.NamesSymbol = C.R_NamesSymbol
R.ClassSymbol = C.R_ClassSymbol
R.DimSymbol = C.R_DimSymbol
R.DimNamesSymbol = C.R_DimNamesSymbol
R.RowNamesSymbol = C.R_RowNamesSymbol
R.NA_LOGICAL = C.R_NaInt
R.NA_INTEGER = C.R_NaInt
R.NA_REAL = C.R_NaReal
R.NA_STRING = C.R_NaString

-- LuaJIT SEXP type
R.sexp = ffi.typeof("SEXP")

-- R version
R.version = R_version

return R
