-- R API for luajr
-- Entries between === markers managed or read by luajr/local/add_rapi.R

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
const void* DATAPTR_RO(SEXP x);
void DUPLICATE_ATTRIB(SEXP to, SEXP from);
int* INTEGER(SEXP x);
int* LOGICAL(SEXP x);
const char* R_CHAR(SEXP x);
void R_CheckUserInterrupt(void);
void* R_ExternalPtrAddr(SEXP s);
void R_FlushConsole(void);
SEXP R_lsInternal3(SEXP env, Rboolean all, Rboolean sorted);
SEXP R_MakeExternalPtr(void *p, SEXP tag, SEXP prot);
void R_PreserveObject(SEXP object);
int R_ReadConsole(const char* prompt, unsigned char* buf, int buflen, int hist);
void R_ReleaseObject(SEXP object);
void R_removeVarFromFrame(SEXP name, SEXP env);
Rbyte* RAW(SEXP x);
double* REAL(SEXP x);
SEXP Rf_allocVector(SEXPTYPE type, R_xlen_t length);
SEXP Rf_classgets(SEXP vec, SEXP klass);
SEXP Rf_coerceVector(SEXP v, SEXPTYPE type);
SEXP Rf_cons(SEXP car, SEXP cdr);
void Rf_copyMostAttrib(SEXP inp, SEXP ans);
void Rf_defineVar(SEXP symbol, SEXP value, SEXP rho);
SEXP Rf_dimgets(SEXP vec, SEXP val);
SEXP Rf_dimnamesgets(SEXP vec, SEXP val);
SEXP Rf_duplicate(SEXP s);
SEXP Rf_eval(SEXP e, SEXP rho);
SEXP Rf_findFun(SEXP symbol, SEXP rho);
SEXP Rf_getAttrib(SEXP vec, SEXP name);
SEXP Rf_GetOption1(SEXP tag);
Rboolean Rf_inherits(SEXP s, const char* name);
SEXP Rf_install(const char* name);
Rboolean Rf_isObject(SEXP s);
SEXP Rf_lcons(SEXP car, SEXP cdr);
SEXP Rf_mkChar(const char* name);
SEXP Rf_mkCharLen(const char* name, int len);
SEXP Rf_namesgets(SEXP vec, SEXP val);
void Rf_PrintValue(SEXP s);
SEXP Rf_protect(SEXP s);
SEXP Rf_ScalarInteger(int x);
SEXP Rf_ScalarLogical(int x);
SEXP Rf_ScalarReal(double x);
SEXP Rf_ScalarString(SEXP x);
SEXP Rf_setAttrib(SEXP vec, SEXP name, SEXP val);
const char* Rf_type2char(SEXPTYPE t);
void Rf_unprotect(int l);
void SET_STRING_ELT(SEXP x, R_xlen_t i, SEXP v);
void SET_TAG(SEXP x, SEXP y);
SEXP SET_VECTOR_ELT(SEXP x, R_xlen_t i, SEXP v);
void SHALLOW_DUPLICATE_ATTRIB(SEXP to, SEXP from);
SEXP STRING_ELT(SEXP x, R_xlen_t i);
const SEXP* STRING_PTR_RO(SEXP x);
SEXP TAG(SEXP e);
int TYPEOF(SEXP x);
SEXP VECTOR_ELT(SEXP x, R_xlen_t i);
// === end R API declarations ===

// Added post-4.0.0, kept out of the main list above for version-specific loading
// === R late additions ===
SEXP R_NewEnv(SEXP enclos, int hash, int size); // added in 4.1.0
SEXP R_ParentEnv(SEXP x); // added in 4.5.0
SEXP R_getVarEx(SEXP sym, SEXP rho, Rboolean inherits, SEXP ifnotfound); // added in 4.5.0
SEXP R_getRegisteredNamespace(const char* name); // added in 4.6.0
// === end R late additions ===

// Not in public API, included for workarounds with old versions of R.
SEXP Rf_findVar(SEXP symbol, SEXP rho); // used in R.getVarEx, pre-4.5.0
SEXP Rf_findVarInFrame(SEXP rho, SEXP symbol); // used in R.getVarEx, pre-4.5.0
SEXP Rf_NewEnvironment(SEXP namelist, SEXP valuelist, SEXP rho); // used in R.NewEnv, pre-4.1.0
// SEXP Rf_NewHashedEnv(SEXP enclos, ??? size); SEE BELOW
SEXP ENCLOS(SEXP x); // used in R.ParentEnv, pre-4.5.0

// Wrapped below for generic R.length (unexposed to avoid user confusion)
R_xlen_t Rf_xlength(SEXP s);

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

-- R non-public API with changing signatures
if R_version < 40300 then
    -- Used in R.NewEnv, pre-4.1.0
    ffi.cdef [[SEXP R_NewHashedEnv(SEXP enclos, SEXP size);]]
else
    ffi.cdef [[SEXP R_NewHashedEnv(SEXP enclos, int size);]]
end


-- Resolve R API symbols. On POSIX, R loads libR with RTLD_GLOBAL so its
-- symbols are reachable via the default C namespace (dlsym(RTLD_DEFAULT, ...)).
-- On Windows there is no equivalent, so load R.dll directly.
local C
if ffi.os == "Windows" then
    C = ffi.load(R_dll_path)
else
    C = ffi.C
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
R.CheckUserInterrupt = C.R_CheckUserInterrupt
R.classgets = C.Rf_classgets
R.coerceVector = C.Rf_coerceVector
R.cons = C.Rf_cons
R.copyMostAttrib = C.Rf_copyMostAttrib
R.DATAPTR_RO = C.DATAPTR_RO
R.defineVar = C.Rf_defineVar
R.dimgets = C.Rf_dimgets
R.dimnamesgets = C.Rf_dimnamesgets
R.duplicate = C.Rf_duplicate
R.DUPLICATE_ATTRIB = C.DUPLICATE_ATTRIB
R.eval = C.Rf_eval
R.ExternalPtrAddr = C.R_ExternalPtrAddr
R.findFun = C.Rf_findFun
R.FlushConsole = C.R_FlushConsole
R.getAttrib = C.Rf_getAttrib
R.GetOption1 = C.Rf_GetOption1
R.inherits = C.Rf_inherits
R.install = C.Rf_install
R.INTEGER = C.INTEGER
R.isObject = C.Rf_isObject
R.lcons = C.Rf_lcons
R.LOGICAL = C.LOGICAL
R.lsInternal3 = C.R_lsInternal3
R.MakeExternalPtr = C.R_MakeExternalPtr
R.mkChar = C.Rf_mkChar
R.mkCharLen = C.Rf_mkCharLen
R.namesgets = C.Rf_namesgets
R.PreserveObject = C.R_PreserveObject
R.PrintValue = C.Rf_PrintValue
R.PROTECT = C.Rf_protect
R.RAW = C.RAW
R.ReadConsole = C.R_ReadConsole
R.REAL = C.REAL
R.ReleaseObject = C.R_ReleaseObject
R.removeVarFromFrame = C.R_removeVarFromFrame
R.ScalarInteger = C.Rf_ScalarInteger
R.ScalarLogical = C.Rf_ScalarLogical
R.ScalarReal = C.Rf_ScalarReal
R.ScalarString = C.Rf_ScalarString
R.SET_STRING_ELT = C.SET_STRING_ELT
R.SET_TAG = C.SET_TAG
R.SET_VECTOR_ELT = C.SET_VECTOR_ELT
R.setAttrib = C.Rf_setAttrib
R.SHALLOW_DUPLICATE_ATTRIB = C.SHALLOW_DUPLICATE_ATTRIB
R.STRING_ELT = C.STRING_ELT
R.STRING_PTR_RO = C.STRING_PTR_RO
R.TAG = C.TAG
R.type2char = C.Rf_type2char
R.TYPEOF = C.TYPEOF
R.UNPROTECT = C.Rf_unprotect
R.VECTOR_ELT = C.VECTOR_ELT
-- === end R API bindings ===

-- back-compatible R_getVarEx(SEXP sym, SEXP rho, Rboolean inherits, SEXP ifnotfound)
R.getVarEx = function(sym, rho, inherits, ifnotfound)
    if R_version < 40500 then
        -- pre 4.5.0: Rf_findVar or Rf_findVarInFrame (non-API)
        local val
        if inherits == 0 then
            val = C.Rf_findVarInFrame(rho, sym) -- rho first is correct
        else
            val = C.Rf_findVar(sym, rho) -- sym first is correct
        end
        -- force promises
        if val ~= R.UnboundValue and R.TYPEOF(val) == R.PROMSXP then
            -- NB GlobalEnv here is ignored; Rf_eval on a promise uses PRENV().
            val = R.eval(val, R.GlobalEnv)
        end

        return val == R.UnboundValue and ifnotfound or val
    else
        -- 4.5.0 and later: R_getVarEx
        -- NB no forcing needed
        return C.R_getVarEx(sym, rho, inherits, ifnotfound)
    end
end

-- back-compatible R_getRegisteredNamespace(SEXP name)
R.getRegisteredNamespace = function(name)
    if R_version < 40600 then
        -- pre 4.6.0: use back-compatible R.getVarEx
        return R.getVarEx(R.install(name), R.NamespaceRegistry, 0, R.NilValue)
    else
        -- 4.6.0 and later: R.getRegisteredNamespace
        return C.R_getRegisteredNamespace(name)
    end
end

-- back-compatible R_NewEnv(SEXP parent, int hash, int size)
R.NewEnv = function(parent, hash, size)
    if R_version < 40100 then
        -- pre 4.1.0: Rf_NewEnvironment or R_NewHashedEnv (non-API)
        if hash == 0 then
            return C.Rf_NewEnvironment(R.NilValue, R.NilValue, parent)
        else
            return C.R_NewHashedEnv(parent, R.ScalarInteger(size))
        end
    else
        -- 4.1.0 and later: R_NewEnv
        return C.R_NewEnv(parent, hash, size)
    end
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

-- needed as there is no replacement for SET_ENCLOS as of R 4.6.0
R.set_parent = function(env, parent)
    local set_parent_fn = R.findFun(R.install("parent.env<-"), R.BaseEnv)
    local call = R.PROTECT(R.lcons(set_parent_fn, R.cons(env, R.cons(parent, R.NilValue))))
    R.eval(call, R.GlobalEnv)
    R.UNPROTECT(1)
end

-- Convert 64-bit length to Lua number
R.length = function(sexp)
    return tonumber(C.Rf_xlength(sexp))
end

-- SEXP type name as string
R.type_string = function(sexp)
    return ffi.string(C.Rf_type2char(C.TYPEOF(sexp)))
end

-- R constants
R.TRUE = 1
R.FALSE = 0
R.NilValue = C.R_NilValue
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

-- R version
R.version = R_version

-- LuaJIT SEXP type
R.sexp = ffi.typeof("SEXP")

return R
