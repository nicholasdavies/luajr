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
#include <R_ext/Altrep.h>

// Reference types
typedef struct { int* _p;    SEXP _s; } logical_rt;
typedef struct { int* _p;    SEXP _s; } integer_rt;
typedef struct { double* _p; SEXP _s; } numeric_rt;
typedef struct { SEXP _s; } character_rt;

// Vector types
typedef struct { int* p;    double n; double c; } logical_vt;
typedef struct { int* p;    double n; double c; } integer_vt;
typedef struct { double* p; double n; double c; } numeric_vt;
// Character vector is defined in luajr.lua as a table

// NA definitions
int TRUE_logical = 0;
int FALSE_logical = 1;
int NA_logical = NA_LOGICAL;
int NA_integer = NA_INTEGER;
double NA_real = NA_REAL;
SEXP NA_character = NA_STRING;

// Compact integer range altrep class -- in R's altclasses.c
extern R_altrep_class_t R_compact_intseq_class;

// Directly from altclasses.c (but less horrifically indented etc) from 4.4.0-devel
static SEXP new_compact_intseq(R_xlen_t n, int n1, int inc)
{
    if (n == 1)
        return Rf_ScalarInteger(n1);

    if (inc != 1 && inc != -1)
	    Rf_error("compact sequences with increment %d not supported yet", inc);

    // info used REALSXP to allow for long vectors
    SEXP info = Rf_allocVector(REALSXP, 3);
    REAL0(info)[0] = (double) n;
    REAL0(info)[1] = (double) n1;
    REAL0(info)[2] = (double) inc;

    SEXP ans = R_new_altrep(R_compact_intseq_class, info, R_NilValue);
    MARK_NOT_MUTABLE(ans); // force duplicate on modify

    return ans;
}


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

extern "C" void AllocLogical(logical_rt* x, ptrdiff_t size)
{
    x->_s = Rf_allocVector3(LGLSXP, size, 0);
    R_PreserveObject(x->_s);
    x->_p = LOGICAL(x->_s) - 1;
}

extern "C" void AllocInteger(integer_rt* x, ptrdiff_t size)
{
    x->_s = Rf_allocVector3(INTSXP, size, 0);
    R_PreserveObject(x->_s);
    x->_p = INTEGER(x->_s) - 1;
}

extern "C" void AllocIntegerCompact1N(integer_rt* x, ptrdiff_t N)
{
    if (N > 0)
    {
        x->_s = new_compact_intseq(N, 1, 1);
        R_PreserveObject(x->_s);
        x->_p = 0;
    }
    else
    {
        x->_s = R_NilValue;
        x->_p = 0;
    }
}

extern "C" void AllocNumeric(numeric_rt* x, ptrdiff_t size)
{
    x->_s = Rf_allocVector3(REALSXP, size, 0);
    R_PreserveObject(x->_s);
    x->_p = REAL(x->_s) - 1;
}

extern "C" void AllocCharacter(character_rt* x, ptrdiff_t size)
{
    x->_s = Rf_allocVector3(STRSXP, size, 0);
    R_PreserveObject(x->_s);
}

extern "C" void AllocCharacterTo(character_rt* x, ptrdiff_t size, const char* v)
{
    x->_s = Rf_allocVector3(STRSXP, size, 0);
    R_PreserveObject(x->_s);
    SEXP sv = PROTECT(Rf_mkChar(v));
    for (ptrdiff_t i = 0; i < size; ++i)
        SET_STRING_ELT(x->_s, i, sv);
    UNPROTECT(1);
}

extern "C" void Release(SEXP s)
{
    R_ReleaseObject(s);
}

extern "C" void SetLogicalVec(logical_vt* x, SEXP s)
{
    std::memcpy(x->p + 1, LOGICAL(s), sizeof(int) * Rf_xlength(s));
}

extern "C" void SetIntegerVec(integer_vt* x, SEXP s)
{
    std::memcpy(x->p + 1, INTEGER(s), sizeof(int) * Rf_xlength(s));
}

extern "C" void SetNumericVec(numeric_vt* x, SEXP s)
{
    std::memcpy(x->p + 1, REAL(s), sizeof(double) * Rf_xlength(s));
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

extern "C" double SEXP_length(SEXP s)
{
    return Rf_xlength(s);
}
