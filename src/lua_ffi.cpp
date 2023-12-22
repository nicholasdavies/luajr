// Functions designed to be called from Lua code using the LuaJIT FFI.

#include "shared.h"
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// Create compact integer range (for rownames of data.frame)
extern "C" SEXP R_compact_intrange(R_xlen_t n1, R_xlen_t n2);

// -----------
// API for Lua
// -----------

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
        ptrs[c] = (double*)DATAPTR(m) + nrow * c;
        ((SEXP*)DATAPTR(colnames))[c] = Rf_mkChar(names[c]);
    }
    SEXP dimnames = PROTECT(Rf_allocVector3(VECSXP, 2, NULL));
    ((SEXP*)DATAPTR(dimnames))[0] = R_NilValue;
    ((SEXP*)DATAPTR(dimnames))[1] = colnames;
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
    // We use '((SEXP*)DATAPTR(x))[i] = v;' throughout, which is fine so long as
    // x is not an altrep vector, by memory.c definition of SET_VECTOR_ELT_0.

    // Create data.frame directly
    SEXP df = PROTECT(Rf_allocVector3(VECSXP, ncol, NULL));
    SEXP colnames = PROTECT(Rf_allocVector3(STRSXP, ncol, NULL));

    // Allocate each column
    for (unsigned int c = 0; c < ncol; ++c)
    {
        SEXP column = Rf_allocVector3(REALSXP, nrow, NULL);
        ((SEXP*)DATAPTR(df))[c] = column;
        ptrs[c] = (double*)DATAPTR(column);
        ((SEXP*)DATAPTR(colnames))[c] = Rf_mkChar(names[c]);
    }

    // Set names
    Rf_setAttrib(df, R_NamesSymbol, colnames);

    // Set class
    SEXP attr_class = PROTECT(Rf_allocVector3(STRSXP, 1, NULL));
    ((SEXP*)DATAPTR(attr_class))[0] = Rf_mkChar("data.frame");
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
