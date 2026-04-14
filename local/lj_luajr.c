/* lj_luajr.c
 * luajr-specific extensions to LuaJIT. Exports functions for luajr to use.
 * (C) 2026 Nicholas G. Davies
 */

#ifndef _BUILDVM_H

#include "lua.h"
#include "lj_obj.h"
#include "lj_gc.h"
#include "lj_str.h"
#include "lj_ctype.h"
#include "lj_cdata.h"
#include "lj_state.h"
#include <stddef.h>  /* ptrdiff_t */

/* R SEXPTYPE codes; must match Rinternals.h. */
#define LGLSXP   10
#define INTSXP   13
#define REALSXP  14
#define STRSXP   16

/* Cached CTypeIDs for SEXP and the four luajr vector types. Populated on
 * first use; consistent across states because R.lua / luajr.lua's cdef order is
 * deterministic (these typedefs are among the very first declared). */
static CTypeID luajr_sexp_ctype_id = 0;
static CTypeID luajr_logical_ctype_id = 0;
static CTypeID luajr_integer_ctype_id = 0;
static CTypeID luajr_numeric_ctype_id = 0;
static CTypeID luajr_character_ctype_id = 0;

/* Common memory layout for all four luajr vector types (logical_t,
 * integer_t, numeric_t, character_t). They differ only in the type of
 * their first field (a data pointer), but the offsets of s, n, c are
 * the same. */
typedef struct {
    void *p;
    void *s;     /* SEXP */
    double n;    /* current logical length */
    double c;    /* current allocated capacity */
} luajr_vector_t;

/* Look up a typedef name in the FFI ctype table and return the resolved
 * underlying CTypeID (matching what ffi.typeof("name") returns). */
static CTypeID luajr_lookup_typedef(CTState *cts, GCstr *name)
{
    CType *ct;
    /* Search FFI name index for a CT_TYPEDEF with this interned name. */
    CTypeID id = lj_ctype_getname(cts, &ct, name, 1u << CT_TYPEDEF);
    /* ct->info packs (kind, child_id); ctype_cid extracts the child id,
     * i.e. the type the typedef aliases. */
    return id ? ctype_cid(ct->info) : 0;
}

/* Populate all cached CTypeIDs (run once per process). */
static void luajr_ensure_ctype_ids(lua_State *L)
{
    if (luajr_sexp_ctype_id != 0) return;
    /* ctype_cts(L) returns this VM's per-state CType table. */
    CTState *cts = ctype_cts(L);
    /* lj_str_newlit interns the literal as a GCstr (cheap on later calls). */
    luajr_sexp_ctype_id      = luajr_lookup_typedef(cts, lj_str_newlit(L, "SEXP"));
    luajr_logical_ctype_id   = luajr_lookup_typedef(cts, lj_str_newlit(L, "logical_t"));
    luajr_integer_ctype_id   = luajr_lookup_typedef(cts, lj_str_newlit(L, "integer_t"));
    luajr_numeric_ctype_id   = luajr_lookup_typedef(cts, lj_str_newlit(L, "numeric_t"));
    luajr_character_ctype_id = luajr_lookup_typedef(cts, lj_str_newlit(L, "character_t"));
}

/* Push a SEXP (passed as void*) onto the Lua stack as a cdata of type SEXP. */
extern void luajr_push_sexp_cdata(lua_State *L, void *x)
{
    luajr_ensure_ctype_ids(L);
    CTState *cts = ctype_cts(L);
    /* Allocate a GCcdata header + sizeof(void*) value bytes, tagged SEXP. */
    GCcdata *cd = lj_cdata_new(cts, luajr_sexp_ctype_id, sizeof(void *));
    /* cdataptr(cd) is the start of the value bytes after the header. */
    *(void **)cdataptr(cd) = x;
    /* Write a cdata-typed TValue into the slot at L->top. */
    setcdataV(L, L->top, cd);
    /* Advance L->top by one TValue slot (i.e. lua_push* "commits" the push). */
    incr_top(L);
    /* Run a GC step if our allocation crossed the GC trigger threshold. */
    lj_gc_check(L);
}

/* Push a luajr vector cdata (logical_t/integer_t/numeric_t/character_t) onto
 * the Lua stack with the given (p, s, n, c) field values. sxp_type selects
 * which vector ctype to use; values match R's SEXPTYPE codes (LGLSXP=10,
 * INTSXP=13, REALSXP=14, STRSXP=16). The caller is responsible for computing
 * the field values, including the -1-element offset on p for 1-based Lua
 * indexing. */
extern void luajr_push_vector_cdata(lua_State *L, int sxp_type,
                                    void *p, void *s, double n, double c)
{
    luajr_ensure_ctype_ids(L);
    CTState *cts = ctype_cts(L);
    /* Map R's SEXPTYPE to the corresponding cached vector ctype id. */
    CTypeID id;
    switch (sxp_type)
    {
        case LGLSXP:  id = luajr_logical_ctype_id;   break;
        case INTSXP:  id = luajr_integer_ctype_id;   break;
        case REALSXP: id = luajr_numeric_ctype_id;   break;
        case STRSXP:  id = luajr_character_ctype_id; break;
        default: return;  /* unknown: leave stack unchanged */
    }
    GCcdata *cd = lj_cdata_new(cts, id, sizeof(luajr_vector_t));
    luajr_vector_t *v = (luajr_vector_t *)cdataptr(cd);
    v->p = p;
    v->s = s;
    v->n = n;
    v->c = c;
    setcdataV(L, L->top, cd);
    incr_top(L);
    lj_gc_check(L);
}

/* Extract a SEXP from the cdata at the given Lua stack index. Handles bare
 * SEXP cdata, the four luajr vector types (logical_t/integer_t/numeric_t/
 * character_t), and any pointer-type cdata with a NULL value (the `nullptr`
 * idiom used in luajr.lua, returned to R as R_NilValue).
 *
 * The SEXP is written to *out_s on success. The return value is:
 *   >= 0 : recognized; the SEXP needs to be shrunk to this length before
 *          returning to R (i.e. n < c for a vector cdata).
 *     -1 : recognized; no shrink needed.
 *     -2 : not a recognized cdata type.
 *
 * This function never modifies the vector cdata. The caller (in push_to.cpp,
 * with R headers in scope) is responsible for any shrink-to-fit allocation. */
extern ptrdiff_t luajr_get_sexp_cdata(lua_State *L, int index, void **out_s)
{
    luajr_ensure_ctype_ids(L);
    /* Slot N (1-based, positive) lives at L->base + N - 1; if past L->top
     * the slot doesn't exist, so substitute the sentinel nil TValue. */
    TValue *o = L->base + (index - 1);
    o = o < L->top ? o : niltv(L);
    /* tviscdata checks the TValue's tag bits. */
    if (!tviscdata(o)) return -2;
    /* cdataV extracts the GCcdata* the TValue refers to. */
    GCcdata *cd = cdataV(o);
    CTypeID id = cd->ctypeid;
    if (id == luajr_sexp_ctype_id)
    {
        /* Stored value is one void* in the bytes after the header. */
        *out_s = *(void **)cdataptr(cd);
        return -1;
    }
    if (id == luajr_logical_ctype_id || id == luajr_integer_ctype_id ||
        id == luajr_numeric_ctype_id || id == luajr_character_ctype_id)
    {
        /* Stored value follows luajr_vector_t layout. */
        luajr_vector_t *v = (luajr_vector_t *)cdataptr(cd);
        *out_s = v->s;
        return (v->n < v->c) ? (ptrdiff_t)v->n : -1;
    }
    /* Any other pointer-type cdata with a NULL value is treated as R_NilValue.
     * This covers the `nullptr` (void* with 0) idiom used in luajr.lua. */
    {
        CTState *cts = ctype_cts(L);
        /* Look up the CType by its id; ctype_isptr tests info kind == CT_PTR. */
        CType *ct = ctype_get(cts, id);
        if (ctype_isptr(ct->info) && *(void **)cdataptr(cd) == NULL)
        {
            *out_s = NULL;
            return -1;
        }
    }
    return -2;
}

#endif /* _BUILDVM_H */
