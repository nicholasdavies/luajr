-- R API for luajr
-- Entries between === markers managed by add_rapi() in luajr/local/add_rapi.R

local ffi = require("ffi")

-- Script receives the R version as argument, e.g. 4.5.3 -> 40503
local R_version = ({...})[1]

-- Script also receives the path to the luajr R package dylib as argument
local luajr_dylib_path = ({...})[2]

-- Script also receives the path to the R DLL as argument (Windows only)
local R_dll_path = ({...})[3]

-- Declarations
ffi.cdef[[
// SEXP
struct SEXPREC;
typedef struct SEXPREC* SEXP;
typedef ptrdiff_t R_xlen_t;
typedef unsigned int SEXPTYPE;
typedef unsigned char Rbyte;
typedef int Rboolean;

// === R API declarations ===
const void *DATAPTR_RO(SEXP x);
void DUPLICATE_ATTRIB(SEXP to, SEXP from);
int* INTEGER(SEXP x);
int* LOGICAL(SEXP x);
const char* R_CHAR(SEXP x);
void *R_ExternalPtrAddr(SEXP s);
void R_FlushConsole(void);
SEXP R_lsInternal(SEXP, Rboolean);
SEXP R_MakeExternalPtr(void *p, SEXP tag, SEXP prot);
void R_PreserveObject(SEXP);
int R_ReadConsole(const char* prompt, unsigned char* buf, int buflen, int hist);
void R_ReleaseObject(SEXP);
void R_removeVarFromFrame(SEXP, SEXP);
Rbyte *RAW(SEXP x);
double* REAL(SEXP x);
SEXP Rf_allocVector(SEXPTYPE, R_xlen_t);
SEXP Rf_cons(SEXP, SEXP);
void Rf_copyMostAttrib(SEXP, SEXP);
void Rf_defineVar(SEXP, SEXP, SEXP);
SEXP Rf_dimnamesgets(SEXP, SEXP);
SEXP Rf_eval(SEXP, SEXP);
SEXP Rf_findFun(SEXP, SEXP);
SEXP Rf_getAttrib(SEXP, SEXP);
SEXP Rf_install(const char*);
SEXP Rf_lcons(SEXP, SEXP);
SEXP Rf_mkChar(const char*);
SEXP Rf_mkCharLen(const char *, int);
SEXP Rf_protect(SEXP);
SEXP Rf_ScalarLogical(int);
SEXP Rf_ScalarReal(double);
SEXP Rf_ScalarString(SEXP);
SEXP Rf_setAttrib(SEXP, SEXP, SEXP);
const char* Rf_type2char(SEXPTYPE);
void Rf_unprotect(int);
void SET_STRING_ELT(SEXP x, R_xlen_t i, SEXP v);
SEXP SET_VECTOR_ELT(SEXP x, R_xlen_t i, SEXP v);
void SHALLOW_DUPLICATE_ATTRIB(SEXP to, SEXP from);
SEXP STRING_ELT(SEXP x, R_xlen_t i);
const SEXP *STRING_PTR_RO(SEXP x);
int TYPEOF(SEXP x);
SEXP VECTOR_ELT(SEXP x, R_xlen_t i);
// === end R API declarations ===

// Not in public API, included for workarounds with old versions of R.
SEXP Rf_findVarInFrame(SEXP, SEXP); // used in R.get_namespace, pre-4.5.0
SEXP Rf_NewEnvironment(SEXP, SEXP, SEXP); // used in R.new_env, pre-4.1.0
SEXP ENCLOS(SEXP x); // used in R.ParentEnv, pre-4.5.0

// Added post-4.0.0, kept out of the main list above for version-specific loading
SEXP R_NewEnv(SEXP, int, int); // added in 4.1.0
SEXP R_ParentEnv(SEXP); // added in 4.5.0
SEXP R_getVar(SEXP, SEXP, Rboolean); // added in 4.5.0
SEXP R_getVarEx(SEXP, SEXP, Rboolean, SEXP); // added in 4.5.0
SEXP R_getRegisteredNamespace(const char*); // added in 4.6.0

// Wrapped below for generic R.length (unexposed to avoid user confusion)
R_xlen_t Rf_xlength(SEXP);

// R constants -- bound manually below
extern SEXP R_NilValue;
extern int R_NaInt;
extern double R_NaReal;
extern SEXP R_NaString;
extern SEXP R_UnboundValue;
extern SEXP R_MissingArg;
extern SEXP R_GlobalEnv;
extern SEXP R_EmptyEnv;
extern SEXP R_BaseEnv;
extern SEXP R_BlankString;
extern SEXP R_NamesSymbol;
extern SEXP R_ClassSymbol;
extern SEXP R_DimSymbol;
extern SEXP R_DimNamesSymbol;
extern SEXP R_RowNamesSymbol;
extern SEXP R_NamespaceRegistry;
]]

-- Resolve R API symbols. On Windows, the luajr dylib doesn't re-export R's
-- symbols, so load R's shared library directly.
local C
if ffi.os == "Windows" then
    C = ffi.load(R_dll_path)
else
    C = ffi.load(luajr_dylib_path)
end

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
R.cons = C.Rf_cons
R.copyMostAttrib = C.Rf_copyMostAttrib
R.DATAPTR_RO = C.DATAPTR_RO
R.defineVar = C.Rf_defineVar
R.dimnamesgets = C.Rf_dimnamesgets
R.DUPLICATE_ATTRIB = C.DUPLICATE_ATTRIB
R.eval = C.Rf_eval
R.ExternalPtrAddr = C.R_ExternalPtrAddr
R.findFun = C.Rf_findFun
R.FlushConsole = C.R_FlushConsole
R.getAttrib = C.Rf_getAttrib
R.install = C.Rf_install
R.INTEGER = C.INTEGER
R.lcons = C.Rf_lcons
R.LOGICAL = C.LOGICAL
R.lsInternal = C.R_lsInternal
R.MakeExternalPtr = C.R_MakeExternalPtr
R.mkChar = C.Rf_mkChar
R.mkCharLen = C.Rf_mkCharLen
R.PreserveObject = C.R_PreserveObject
R.PROTECT = C.Rf_protect
R.RAW = C.RAW
R.ReadConsole = C.R_ReadConsole
R.REAL = C.REAL
R.ReleaseObject = C.R_ReleaseObject
R.removeVarFromFrame = C.R_removeVarFromFrame
R.ScalarLogical = C.Rf_ScalarLogical
R.ScalarReal = C.Rf_ScalarReal
R.ScalarString = C.Rf_ScalarString
R.SET_STRING_ELT = C.SET_STRING_ELT
R.SET_VECTOR_ELT = C.SET_VECTOR_ELT
R.setAttrib = C.Rf_setAttrib
R.SHALLOW_DUPLICATE_ATTRIB = C.SHALLOW_DUPLICATE_ATTRIB
R.STRING_ELT = C.STRING_ELT
R.STRING_PTR_RO = C.STRING_PTR_RO
R.type2char = C.Rf_type2char
R.TYPEOF = C.TYPEOF
R.UNPROTECT = C.Rf_unprotect
R.VECTOR_ELT = C.VECTOR_ELT
-- === end R API bindings ===

-- R API bindings introduced in specific versions > 4.0.0
if R_version >= 40100 then
    R.NewEnv = C.R_NewEnv
end

if R_version >= 40500 then
    R.getVar = C.R_getVar
    R.getVarEx = C.R_getVarEx
end

if R_version >= 40600 then
    R.getRegisteredNamespace = C.R_getRegisteredNamespace
end

-- Convert 64-bit length to Lua number
R.length = function(sexp)
    return tonumber(C.Rf_xlength(sexp))
end

-- SEXP type name as string
R.type_string = function(sexp)
    return ffi.string(C.Rf_type2char(C.TYPEOF(sexp)))
end

R.get_var = function(name, env)
    local val
    if R_version < 40500 then
        -- pre 4.5.0: Rf_findVarInFrame (non-API)
        val = C.Rf_findVarInFrame(env, R.install(name))
        -- force promises
        if val ~= R.UnboundValue and R.TYPEOF(val) == R.PROMSXP then
            val = R.eval(val, R.GlobalEnv)
        end
    else
        -- 4.5.0 and later: R.getVarEx
        val = R.getVarEx(R.install(name), env, 1, R.UnboundValue)
        -- passed force=1 above, no forcing needed
    end
    if val == R.UnboundValue then return nil end
    return val
end

R.get_namespace = function(name)
    local env
    if R_version < 40600 then
        -- pre 4.6.0: R.get_var
        env = R.get_var(name, R.NamespaceRegistry)
    else
        -- 4.6.0 and later: R.getRegisteredNamespace
        env = R.getRegisteredNamespace(name)
    end

    if not env or env == R.NilValue then
        error("could not find namespace " .. name)
    end

    return env
end

R.new_env = function(parent)
    parent = parent or C.R_EmptyEnv
    if R_version < 40100 then
        -- pre 4.1.0: Rf_NewEnvironment (non-API)
        return C.Rf_NewEnvironment(R.NilValue, R.NilValue, parent)
    else
        -- 4.1.0 and later: R_NewEnv
        return R.NewEnv(parent, 1, 29)
    end
end

-- needed as there is no replacement for SET_ENCLOS as of R 4.6.0
R.set_parent = function(env, parent)
    local set_parent_fn = R.findFun(R.install("parent.env<-"), R.BaseEnv)
    local call = R.PROTECT(R.lcons(set_parent_fn, R.cons(env, R.cons(parent, R.NilValue))))
    R.eval(call, R.GlobalEnv)
    R.UNPROTECT(1)
end

-- back-compatible R_ParentEnv
R.ParentEnv = function(x)
    if R_version < 40500 then
        -- pre 4.5.0: ENCLOS (non-API)
        return C.ENCLOS(x)
    else
        -- 4.5.0 and later: R_ParentEnv
        return C.R_ParentEnv(x)
    end
end

-- R constants
R.TRUE = 1
R.FALSE = 0
R.NilValue = C.R_NilValue
R.NULL = C.R_NilValue
R.NA_LOGICAL = C.R_NaInt
R.NA_INTEGER = C.R_NaInt
R.NA_REAL = C.R_NaReal
R.NA_STRING = C.R_NaString
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
R.NamespaceRegistry = C.R_NamespaceRegistry

-- LuaJIT SEXP type
R.sexp = ffi.typeof("SEXP")

-- R version
R.version = R_version

return R
