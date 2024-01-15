// Functions designed to be called from Lua code using the LuaJIT FFI.

#include "shared.h"
#include <vector>
#include <iostream>
extern "C" {
#include "lua.h"
}
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// TODO do typedefs for underlying logical, integer, numeric types???

// Reference types
typedef struct { int* _p;    SEXP _s; } logical_rt;
typedef struct { int* _p;    SEXP _s; } integer_rt;
typedef struct { double* _p; SEXP _s; } numeric_rt;
typedef struct { SEXP _s; } character_rt;

// Vector types
typedef struct { int* p;    uint32_t n; uint32_t c; } logical_vt;
typedef struct { int* p;    uint32_t n; uint32_t c; } integer_vt;
typedef struct { double* p; uint32_t n; uint32_t c; } numeric_vt;

// NA definitions
int NA_logical = NA_LOGICAL;
int NA_integer = NA_INTEGER;
double NA_real = NA_REAL;
SEXP NA_character = NA_STRING;

// Create compact integer range (for rownames of data.frame)
extern "C" SEXP R_compact_intrange(R_xlen_t n1, R_xlen_t n2);

// ---------------
// FFI API for Lua
// ---------------

// Note: LOGICAL(x), INTEGER(x), REAL(x), DATAPTR(x), SET_*_ELT() and *_ELT(x)
// are all safe to use on ALTREP types. DATAPTR returns void*, and LOGICAL,
// INTEGER, REAL are just macros for DATAPTR with a cast (i.e. to int*, int*,
// double*). For modifying VECSXP/STRSXP, must use SET_VECTOR_ELT/SET_STRING_ELT
// as these update reference counts to elements; I use VECTOR_ELT/STRING_ELT for
// access, though from R sources this is less critical.

// TODO need to verify type of SEXP throughout, unless it's already guaranteed
extern "C" void SetLogicalRef(logical_rt* x, SEXP s)
{
    x->_p = LOGICAL(s) - 1;
    x->_s = s;
}

extern "C" void SetIntegerRef(integer_rt* x, SEXP s)
{
    x->_p = INTEGER(s) - 1;
    x->_s = s;
}

extern "C" void SetNumericRef(numeric_rt* x, SEXP s)
{
    x->_p = REAL(s) - 1;
    x->_s = s;
}

extern "C" void SetCharacterRef(character_rt* x, SEXP s)
{
    x->_s = s;
}

extern "C" void AllocLogical(logical_rt* x, size_t size)
{
    x->_s = Rf_allocVector3(LGLSXP, size, 0);
    R_PreserveObject(x->_s);
    x->_p = LOGICAL(x->_s) - 1;
}

extern "C" void AllocInteger(integer_rt* x, size_t size)
{
    x->_s = Rf_allocVector3(INTSXP, size, 0);
    R_PreserveObject(x->_s);
    x->_p = INTEGER(x->_s) - 1;
}

extern "C" void AllocNumeric(numeric_rt* x, size_t size)
{
    x->_s = Rf_allocVector3(REALSXP, size, 0);
    R_PreserveObject(x->_s);
    x->_p = REAL(x->_s) - 1;
}

extern "C" void AllocCharacter(character_rt* x, size_t size)
{
    x->_s = Rf_allocVector3(STRSXP, size, 0);
    R_PreserveObject(x->_s);
}

extern "C" void AllocCharacterTo(character_rt* x, size_t size, const char* v)
{
    x->_s = Rf_allocVector3(STRSXP, size, 0);
    R_PreserveObject(x->_s);
    SEXP sv = Rf_mkChar(v);
    for (size_t i = 0; i < size; ++i)
        SET_STRING_ELT(x->_s, i, sv);
}

extern "C" void Release(SEXP s)
{
    R_ReleaseObject(s);
}

extern "C" void SetLogicalVec(logical_vt* x, SEXP s)
{
    std::memcpy(x->p + 1, LOGICAL(s), sizeof(int) * Rf_length(s)); // TODO XLENGTH_EX(s) ?
}

extern "C" void SetIntegerVec(integer_vt* x, SEXP s)
{
    std::memcpy(x->p + 1, INTEGER(s), sizeof(int) * Rf_length(s)); // TODO XLENGTH_EX(s) ?
}

extern "C" void SetNumericVec(numeric_vt* x, SEXP s)
{
    std::memcpy(x->p + 1, REAL(s), sizeof(double) * Rf_length(s)); // TODO XLENGTH_EX(s) ?
}

extern "C" int GetAttrType(SEXP s, const char* k)
{
    SEXP a = Rf_getAttrib(s, Rf_install(k));
    switch (TYPEOF(a))
    {
        case NILSXP:
            return NULL_T;
        case LGLSXP:
            return LOGICAL_T | REFERENCE_T;
        case INTSXP:
            return INTEGER_T | REFERENCE_T;
        case REALSXP:
            return NUMERIC_T | REFERENCE_T;
        case STRSXP:
            return CHARACTER_T | REFERENCE_T;
        default:
            Rf_error("Cannot get attribute of type %s.", Rf_type2char(TYPEOF(a)));
    }
}

extern "C" SEXP GetAttrSEXP(SEXP s, const char* k)
{
    return Rf_getAttrib(s, Rf_install(k));
}

extern "C" void SetAttrLogicalRef(SEXP s, const char* k, logical_rt* v)
{
    Rf_setAttrib(s, Rf_install(k), v->_s);
}

extern "C" void SetAttrIntegerRef(SEXP s, const char* k, integer_rt* v)
{
    Rf_setAttrib(s, Rf_install(k), v->_s);
}

extern "C" void SetAttrNumericRef(SEXP s, const char* k, numeric_rt* v)
{
    Rf_setAttrib(s, Rf_install(k), v->_s);
}

extern "C" void SetAttrCharacterRef(SEXP s, const char* k, character_rt* v)
{
    Rf_setAttrib(s, Rf_install(k), v->_s);
}

extern "C" void SetMatrixColnamesCharacterRef(SEXP s, character_rt* v)
{
    SEXP dimnames = PROTECT(Rf_allocVector3(VECSXP, 2, NULL));
    SET_VECTOR_ELT(dimnames, 0, R_NilValue);
    SET_VECTOR_ELT(dimnames, 1, v->_s);
    Rf_dimnamesgets(s, dimnames);
    UNPROTECT(1);
}

extern "C" const char* GetCharacterElt(SEXP s, ptrdiff_t k)
{
    SEXP x = STRING_ELT(s, k);
    if (x == NA_STRING)
        return 0;
    return CHAR(x);
}

extern "C" void SetCharacterElt(SEXP s, ptrdiff_t k, const char* v)
{
    if (v == 0)
        SET_STRING_ELT(s, k, NA_STRING);
    else
        SET_STRING_ELT(s, k, Rf_mkChar(v));
}

extern "C" void SetPtr(void** ptr, void* val)
{
    *ptr = val;
}

extern "C" int SEXP_length(SEXP s)
{
    return Rf_length(s); // TODO XLENGTH_EX(s) ?
}

extern "C" SEXP CompactRowNames(size_t nrow)
{
    if (nrow > 0)
        return R_compact_intrange(1, nrow);
    return R_NilValue;
}

/* Older code, kept for reference


// Allocate an R numeric matrix, outputting addresses of each column into ptrs.
// The matrix is returned to R via the robj_ret mechanism.
extern "C" int AllocRDataMatrix(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs)
{
    // Create matrix
    SEXP m = PROTECT(Rf_allocMatrix(REALSXP, nrow, ncol));
    SEXP colnames = PROTECT(Rf_allocVector3(STRSXP, ncol, NULL));

    // Set column names and retrieve pointers
    for (unsigned int c = 0; c < ncol; ++c)
    {
        ptrs[c] = REAL(m) + nrow * c;
        SET_STRING_ELT(colnames, c, Rf_mkChar(names[c]));
    }
    SEXP dimnames = PROTECT(Rf_allocVector3(VECSXP, 2, NULL));
    SET_VECTOR_ELT(dimnames, 0, R_NilValue);
    SET_VECTOR_ELT(dimnames, 1, colnames);
    Rf_dimnamesgets(m, dimnames);

    // Assign matrix within robj_ret in calling R environment
    SEXP current_env = R_GetCurrentEnv();
    SEXP robj_ret = Rf_findVar(RObjRetSymbol, current_env);
    int robj_ret_len = Rf_length(robj_ret);
    for (int i = 0; i < robj_ret_len; ++i)
    {
        if (VECTOR_ELT(robj_ret, i) == R_NilValue)
        {
            SET_VECTOR_ELT(robj_ret, i, m);
            UNPROTECT(3);
            return i;
        }
    }

    // No free spaces in robj_ret: grow list
    SEXP new_robj_ret = PROTECT(Rf_allocVector3(VECSXP, robj_ret_len * 2, NULL));
    for (int i = 0; i < robj_ret_len; ++i)
        SET_VECTOR_ELT(new_robj_ret, i, VECTOR_ELT(robj_ret, i));
    SET_VECTOR_ELT(new_robj_ret, robj_ret_len, m);
    Rf_defineVar(RObjRetSymbol, new_robj_ret, current_env);

    UNPROTECT(4);
    return robj_ret_len;
}

// Allocate an R data frame, outputting addresses of each column into ptrs.
// The matrix is returned to R via the robj_ret mechanism.
extern "C" int AllocRDataFrame(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs)
{
    // Create data.frame directly
    SEXP df = PROTECT(Rf_allocVector3(VECSXP, ncol, NULL));
    SEXP colnames = PROTECT(Rf_allocVector3(STRSXP, ncol, NULL));

    // Allocate each column
    for (unsigned int c = 0; c < ncol; ++c)
    {
        SEXP column = Rf_allocVector3(REALSXP, nrow, NULL);
        SET_VECTOR_ELT(df, c, column);
        ptrs[c] = REAL(column);
        SET_STRING_ELT(colnames, c, Rf_mkChar(names[c]));
    }

    // Set names
    Rf_setAttrib(df, R_NamesSymbol, colnames);

    // Set class
    SEXP attr_class = PROTECT(Rf_allocVector3(STRSXP, 1, NULL));
    SET_STRING_ELT(attr_class, 0, Rf_mkChar("data.frame"));
    Rf_classgets(df, attr_class);

    // Set row names
    SEXP attr_rownames = R_compact_intrange(1, nrow); // Alternative: Rcpp::Function("seq_len")(nrow);
    Rf_setAttrib(df, R_RowNamesSymbol, attr_rownames);

    // Assign data.frame within robj_ret in calling R environment
    SEXP current_env = R_GetCurrentEnv();
    SEXP robj_ret = Rf_findVar(RObjRetSymbol, current_env);
    int robj_ret_len = Rf_length(robj_ret);
    for (int i = 0; i < robj_ret_len; ++i)
    {
        if (VECTOR_ELT(robj_ret, i) == R_NilValue)
        {
            SET_VECTOR_ELT(robj_ret, i, df);
            UNPROTECT(3);
            return i;
        }
    }

    // No free spaces in robj_ret: grow list
    SEXP new_robj_ret = PROTECT(Rf_allocVector3(VECSXP, robj_ret_len * 2, NULL));
    for (int i = 0; i < robj_ret_len; ++i)
        SET_VECTOR_ELT(new_robj_ret, i, VECTOR_ELT(robj_ret, i));
    SET_VECTOR_ELT(new_robj_ret, robj_ret_len, df);
    Rf_defineVar(RObjRetSymbol, new_robj_ret, current_env);

    UNPROTECT(4);
    return robj_ret_len;
}

*/
