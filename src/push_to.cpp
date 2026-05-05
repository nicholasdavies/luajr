// push_to.cpp: Move values between R and Lua

#include "shared.h"
#include "registry_entry.h"
#include <vector>
#include <string>
#include <cstring>
#include <limits>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "luajit/src/lj_def.h"
}

// Additional types specific to LuaJIT. From lj_obj.h.
#define LUA_TPROTO	(LUA_TTHREAD+1)
#define LUA_TCDATA	(LUA_TTHREAD+2)


// LuaJIT is Lua 5.1 and lacks lua_absindex; this provides the equivalent.
static inline int abs_index(lua_State* L, int index)
{
    return (index > 0 || index <= LUA_REGISTRYINDEX) ? index : lua_gettop(L) + index + 1;
}

// Stop if length of chr exceeds LuaJIT limits.
void CheckStringLength(SEXP chr)
{
    R_xlen_t xlen = Rf_xlength(chr);
    if (xlen >= LJ_MAX_STR)
        Rf_error("Cannot pass string with more than %d bytes. Requested size: %.0f.", LJ_MAX_STR, (double)xlen);
}

// Push a single element of an R vector as a native Lua value.
// Pushes nil for NA values.
static void push_native_element(lua_State* L, SEXP x, int sxptype, R_xlen_t i)
{
    switch (sxptype)
    {
        case LGLSXP:
            if (LOGICAL_ELT(x, i) == NA_LOGICAL) lua_pushnil(L);
            else lua_pushboolean(L, LOGICAL_ELT(x, i));
            break;
        case INTSXP:
            if (INTEGER_ELT(x, i) == NA_INTEGER) lua_pushnil(L);
            else lua_pushinteger(L, INTEGER_ELT(x, i));
            break;
        case REALSXP:
            if (R_IsNA(REAL_ELT(x, i))) lua_pushnil(L);
            else lua_pushnumber(L, REAL_ELT(x, i));
            break;
        case STRSXP:
            if (STRING_ELT(x, i) == R_NaString) lua_pushnil(L);
            else { CheckStringLength(STRING_ELT(x, i));
                   lua_pushstring(L, CHAR(STRING_ELT(x, i))); }
            break;
        default:
            lua_pushnil(L);
            break;
    }
}

// Helper function to push a vector to the Lua stack.
template <typename Push>
static void push_R_vector(lua_State* L, SEXP x, char as, int type, Push push)
{
    // Get length of vector
    R_xlen_t xlen = Rf_xlength(x);

    switch (as)
    {
        case 'r':
        case 'v':
        {
            // Compute the data pointer with offset for 1-based indexing
            void* p;
            switch (type)
            {
                case LGLSXP:  p = (void*)(LOGICAL(x) - 1); break;
                case INTSXP:  p = (void*)(INTEGER(x) - 1); break;
                case REALSXP: p = (void*)(REAL(x) - 1);    break;
                case STRSXP:  p = (void*)(STRING_PTR(x) - 1); break;
                default: Rf_error("Unknown vector type for push_R_vector.");
            }
            // c flag: -1 = byref, -2 = alias; must match 1_vector.lua
            double c_val = (as == 'r') ? -1.0 : -2.0;
            luajr_push_vector_cdata(L, type, p, (void*)x, (double)xlen, c_val);
            break;
        }

        case 's':
        case 'a':
            if (xlen == 0)
                lua_pushnil(L); // Length 0: push nil
            else if (xlen == 1 && as == 's')
                push(L, x, 0);  // Length 1 and 's': push scalar
            else if (xlen < LJ_MAX_ASIZE) // Strict < needed here.
            {                   // Length >1 or 'a': push table
                lua_createtable(L, xlen, 0);
                for (R_xlen_t i = 0; i < xlen; ++i)
                {
                    push(L, x, i);
                    lua_rawseti(L, -2, i + 1);
                }
            }
            else
                Rf_error("Cannot create Lua table with more than %d elements. Requested size: %.0f. Use 'r' or 'v' arg code instead.",
                    LJ_MAX_ASIZE - 1, (double)xlen);
            break;

        default:
            if (as >= '1' && as <= '9')
            {
                int reqn = as - '0';
                if (xlen != reqn)
                    Rf_error("Vector of length %d requested, but passed vector of length %.0f.", reqn, (double)xlen);
                push_R_vector(L, x, 's', type, push);
                break;
            }
            Rf_error("Unrecognised args code %c for type %s.", as, Rf_type2char(TYPEOF(x)));
            break;
    }
}

// Helper function to push a list to the Lua stack.
// Push an R list (VECSXP) as a Lua table, preserving names as string keys.
static void push_list_as_table(lua_State* L, SEXP x)
{
    // Get length of vector
    R_xlen_t xlen = Rf_xlength(x);
    if (xlen >= LJ_MAX_ASIZE || xlen >= std::numeric_limits<int>::max())
        Rf_error("List is too large to be passed to Lua. Cannot create Lua table with more than %d elements. Requested size: %.0f.",
            LJ_MAX_ASIZE - 1, (double)xlen);
    int len = Rf_length(x);

    // Get names of list elements
    // NOTE: The PROTECT call here isn't needed, except to prevent rchk from
    // issuing a false-positive warning.
    SEXP names = PROTECT(Rf_getAttrib(x, R_NamesSymbol));
    if (names != R_NilValue && TYPEOF(names) != STRSXP)
        Rf_error("Non-character names attribute on vector.");

    // Count number of elements with non-empty names
    unsigned int n_named = 0;
    if (names != R_NilValue)
    {
        for (int i = 0; i < len; ++i)
            if (LENGTH(STRING_ELT(names, i)) > 0)
                ++n_named;
    }

    // Create a table on the stack with len elements, len - n_named of
    // which are 'arr' elements and n_named of which are 'rec' elements.
    lua_createtable(L, len - n_named, n_named);

    // This moves through the vector backwards so that if there are repeated
    // names, the earlier vector element with that name takes precedence.
    for (int i = len - 1; i >= 0; --i)
    {
        if (names != R_NilValue && LENGTH(STRING_ELT(names, i)) > 0)
        {
            // Add string-indexed element
            lua_pushstring(L, CHAR(STRING_ELT(names, i)));
            luajr_pushsexp(L, VECTOR_ELT(x, i), AC::value | AC::native);
            lua_rawset(L, -3);
        }
        else
        {
            // Add integer-indexed element
            luajr_pushsexp(L, VECTOR_ELT(x, i), AC::value | AC::native);
            lua_rawseti(L, -2, i + 1);
        }
    }

    UNPROTECT(1);
}

// Inline fast path for 'r'/'v' on atomic vector types: skip push_R_vector
// dispatch entirely and go straight to luajr_push_vector_cdata.
static inline void push_R_vector_rv(lua_State* L, SEXP x, double c_val, int type, void* p)
{
    luajr_push_vector_cdata(L, type, p, (void*)x, (double)Rf_xlength(x), c_val);
}

// Analogous to Lua's lua_pushXXX(lua_State* L, XXX x) functions, this pushes
// the R object [x] onto Lua's stack.
// Supported with conversions to Lua types: NILSXP, LGLSXP, INTSXP, REALSXP,
// STRSXP, VECSXP, EXTPTRSXP, RAWSXP, CLOSXP, ENVSXP, SPECIALSXP, BUILTINSXP.
// Supported only as SEXP: SYMSXP, LISTSXP, PROMSXP, LANGSXP, CHARSXP, CPLXSXP,
// DOTSXP, ANYSXP, EXPRSXP, BCODESXP, WEAKREFSXP, S4SXP.
extern "C" void luajr_pushsexp(lua_State* L, SEXP x, unsigned char as)
{
    int type = as & AC::type_mask;
    bool is_native = as & AC::native;
    bool is_ref    = as & AC::reference;
    bool is_strict = as & AC::strict;

    // NULL handling: strict errors, native pushes nil, non-native pushes R_NilValue SEXP.
    if (TYPEOF(x) == NILSXP)
    {
        if (is_strict)
            Rf_error("NULL passed where a value was required (strict argcode).");
        if (is_native)
            lua_pushnil(L);
        else
            luajr_push_sexp_cdata(L, (void*)R_NilValue);
        return;
    }

    switch (type)
    {
        case AC::sexp:
            luajr_push_sexp_cdata(L, (void*)x);
            break;

        case AC::value:
        {
            int specific;
            switch (TYPEOF(x))
            {
                case LGLSXP:     specific = AC::logical; break;
                case INTSXP:     specific = AC::integer; break;
                case REALSXP:    specific = AC::numeric; break;
                case STRSXP:     specific = AC::character; break;
                case VECSXP:     specific = AC::list; break;
                case ENVSXP:     specific = AC::environment; break;
                case CLOSXP:
                case SPECIALSXP:
                case BUILTINSXP: specific = AC::function; break;
                default:         specific = AC::sexp; break;
            }
            if (is_native && Rf_xlength(x) > 1)
                luajr_pushsexp(L, x, AC::native | AC::list);
            else
                luajr_pushsexp(L, x, (as & ~AC::type_mask) | specific);
            break;
        }

        case AC::list:
        {
            if (is_native)
            {
                int sxptype = TYPEOF(x);
                R_xlen_t xlen = Rf_xlength(x);
                if (xlen >= LJ_MAX_ASIZE)
                    Rf_error("Cannot create Lua table with more than %d elements.", LJ_MAX_ASIZE - 1);
                if (sxptype == VECSXP)
                {
                    push_list_as_table(L, x);
                }
                else
                {
                    lua_createtable(L, xlen, 0);
                    for (R_xlen_t i = 0; i < xlen; ++i)
                    {
                        push_native_element(L, x, sxptype, i);
                        lua_rawseti(L, -2, i + 1);
                    }
                }
            }
            else
            {
                if (TYPEOF(x) != VECSXP)
                    Rf_error("Expected list, got %s.", Rf_type2char(TYPEOF(x)));
                double c_val = is_ref ? -1.0 : -2.0;
                push_R_vector_rv(L, x, c_val, VECSXP, (void*)((SEXP*)DATAPTR(x) - 1));
            }
            break;
        }

        case AC::logical:
        case AC::integer:
        case AC::numeric:
        case AC::character:
        {
            static const int type_to_sxp[] = {
                [AC::logical]   = LGLSXP,
                [AC::integer]   = INTSXP,
                [AC::numeric]   = REALSXP,
                [AC::character] = STRSXP
            };
            int expected = type_to_sxp[type];
            int actual = TYPEOF(x);

            // Coercion (unless strict): integer <-> numeric
            bool coerced = false;
            if (actual != expected && !is_strict)
            {
                if ((expected == INTSXP && actual == REALSXP) ||
                    (expected == REALSXP && actual == INTSXP))
                {
                    x = PROTECT(Rf_coerceVector(x, expected));
                    actual = expected;
                    coerced = true;
                }
            }

            if (actual != expected)
                Rf_error("Expected %s, got %s.", Rf_type2char(expected), Rf_type2char(actual));

            if (is_native)
            {
                R_xlen_t xlen = Rf_xlength(x);
                if (xlen == 0) { lua_pushnil(L); }
                else if (xlen != 1) Rf_error("Expected scalar (length 1), got length %.0f.", (double)xlen);
                else push_native_element(L, x, actual, 0);
            }
            else
            {
                double c_val = is_ref ? -1.0 : -2.0;
                void* p;
                switch (actual) {
                    case LGLSXP:  p = (void*)(LOGICAL(x) - 1); break;
                    case INTSXP:  p = (void*)(INTEGER(x) - 1); break;
                    case REALSXP: p = (void*)(REAL(x) - 1); break;
                    case STRSXP:  p = (void*)(STRING_PTR(x) - 1); break;
                    default:      p = nullptr; break;
                }
                push_R_vector_rv(L, x, c_val, actual, p);
            }

            if (coerced) UNPROTECT(1);
            break;
        }

        case AC::environment:
            if (TYPEOF(x) != ENVSXP)
                Rf_error("Expected environment, got %s.", Rf_type2char(TYPEOF(x)));
            luajr_push_environment_cdata(L, (void*)x);
            break;

        case AC::function:
            if (TYPEOF(x) != CLOSXP && TYPEOF(x) != SPECIALSXP && TYPEOF(x) != BUILTINSXP)
                Rf_error("Expected function, got %s.", Rf_type2char(TYPEOF(x)));
            luajr_push_function_cdata(L, (void*)x);
            break;

        default:
            Rf_error("Unrecognised argcode type %d.", type);
    }
}

// Analogous to Lua's lua_toXXX(lua_State* L, int index) functions, this gets
// the value at [index] on the stack as a SEXP that can be handed to R. Note
// that SEXPs returned from this function need to be protected in calling code.
extern "C" SEXP luajr_tosexp(lua_State* L, int index)
{
    index = abs_index(L, index);

    // Depending on the Lua type of the value at Lua stack index [index],
    // return the corresponding R value.
    switch (lua_type(L, index))
    {
        case LUA_TNIL:
            return R_NilValue;
        case LUA_TBOOLEAN:
            return Rf_ScalarLogical(lua_toboolean(L, index));
        case LUA_TNUMBER:
            return Rf_ScalarReal(lua_tonumber(L, index));
        case LUA_TSTRING:
        {
            // Get string and its length
            size_t len;
            const char* str = lua_tolstring(L, index, &len);

            // If string contains embedded nulls, needs to be returned as a
            // RAWSXP instead of as a STRSXP.
            if (std::strlen(str) != len)
            {
                SEXP retval = PROTECT(Rf_allocVector(RAWSXP, len));
                std::memcpy(RAW(retval), str, len);
                UNPROTECT(1);
                return retval;
            }
            else
            {
                SEXP retval = PROTECT(Rf_allocVector(STRSXP, 1));
                SET_STRING_ELT(retval, 0, Rf_mkCharLen(str, len));
                UNPROTECT(1);
                return retval;
            }
        }
        case LUA_TTABLE:
        {
            // First pass: count table entries of each type.
            size_t narr = 0, nrec = 0;
            lua_pushnil(L);
            while (lua_next(L, index) != 0)
            {
                if      (lua_type(L, -2) == LUA_TNUMBER) ++narr;
                else if (lua_type(L, -2) == LUA_TSTRING) ++nrec;
                else
                    luajr_pop_stop(L, 2, "Lua type %s keys cannot be represented in an R list.",
                        lua_typename(L, lua_type(L, -2)));
                lua_pop(L, 1);
            }

            if (narr + nrec >= LJ_MAX_ASIZE)
                Rf_error("Table is too large to be returned to R. Limit is %d elements. Requested size: %.0f.",
                    LJ_MAX_ASIZE - 1, (double)(narr + nrec));

            // Create list and names
            SEXP retval = PROTECT(Rf_allocVector(VECSXP, narr + nrec));
            SEXP names = R_NilValue;
            if (nrec > 0)
                names = PROTECT(Rf_allocVector(STRSXP, narr + nrec));

            // Second pass: add all entries to list.
            int arr_i = 0, rec_i = narr;
            lua_pushnil(L);
            while (lua_next(L, index) != 0)
            {
                SEXP val = PROTECT(luajr_tosexp(L, -1));
                if (lua_type(L, -2) == LUA_TNUMBER)
                {
                    SET_VECTOR_ELT(retval, arr_i, val);
                    ++arr_i;
                }
                else
                {
                    SET_VECTOR_ELT(retval, rec_i, val);
                    SET_STRING_ELT(names, rec_i, Rf_mkChar(lua_tostring(L, -2)));
                    ++rec_i;
                }
                lua_pop(L, 1);
                UNPROTECT(1);
            }

            // Name and return
            Rf_setAttrib(retval, R_NamesSymbol, names);
            UNPROTECT(1 + (nrec > 0));
            return retval;
        }
        case LUA_TLIGHTUSERDATA:
        case LUA_TUSERDATA:
        case LUA_TTHREAD:
        case LUA_TPROTO:
            return R_MakeExternalPtr(const_cast<void*>(lua_topointer(L, index)), R_NilValue, R_NilValue);
        case LUA_TFUNCTION:
        {
            // Create a copy of the function at stack top
            lua_pushvalue(L, index);
            // Create the registry entry (pops top of stack)
            RegistryEntry* re = new RegistryEntry(L);
            // Send back external pointer to the registry entry
            return luajr_makepointer(re, LUAJR_REGFUNC_CODE, RegistryEntry::Finalize);
        }
        case LUA_TCDATA:
        {
            // Recognized cdata: bare SEXP, a luajr vector type or any null
            // pointer cdata (which becomes R_NilValue).
            SEXP s = NULL;
            ptrdiff_t status = luajr_get_sexp_cdata(L, index, (void**)&s);
            if (status == -2)
                Rf_error("Cannot return cdata of this type to R.");
            if (s == NULL)
                return R_NilValue;

            if (status >= 0 && Rf_xlength(s) != status)
            {
                // Shrink (truncates names, copyMostAttrib for others)
                s = Rf_xlengthgets(s, (R_xlen_t)status);
            }
            // For data.frame, supply a row.names attribute if missing.
            if (TYPEOF(s) == VECSXP && Rf_isObject(s) &&
                Rf_inherits(s, "data.frame") &&
                Rf_getAttrib(s, R_RowNamesSymbol) == R_NilValue)
            {
                // Short-form rownames: c(NA_integer_, nrow) (see attrib.c).
                SEXP rownames = PROTECT(Rf_allocVector(INTSXP, 2));
                INTEGER(rownames)[0] = NA_INTEGER;
                INTEGER(rownames)[1] = Rf_length(VECTOR_ELT(s, 0));
                Rf_setAttrib(s, R_RowNamesSymbol, rownames);
                UNPROTECT(1);
            }
            return s;
        }
        default:
            Rf_error("Unknown return type detected: %d", lua_type(L, index));
    }
}

// Take a list of values passed from R and pass them to Lua
// Specifically, push each of the elements of the list args onto the stack of
// L, using the args code in acode.
extern "C" void luajr_pass(lua_State* L, SEXP args, SEXP acode)
{
    unsigned int acode_length = Rf_length(acode);
    if (acode_length == 0)
        Rf_error("Length of args code is zero.");
    const unsigned char* ac = RAW(acode);
    for (int i = 0; i < Rf_length(args); ++i)
        luajr_pushsexp(L, VECTOR_ELT(args, i), ac[i % acode_length]);
}

// Take values returned from Lua and return them to R
// Specifically, take nret values off the stack of L and wrap them in the
// returned SEXP (either NULL when nret = 0, a single value when nret = 1, or a
// list when nret > 1).
extern "C" SEXP luajr_return(lua_State* L, int nret)
{
    // No return value: return NULL
    if (nret == 0)
    {
        return R_NilValue;
    }
    else if (nret == 1)
    {
        // One return value: convert to SEXP, pop, and return
        SEXP retval = PROTECT(luajr_tosexp(L, -1));
        lua_pop(L, 1);
        UNPROTECT(1);
        return retval;
    }
    else
    {
        // Multiple return values: return as list
        SEXP retlist = PROTECT(Rf_allocVector(VECSXP, nret));

        // Add elements to table
        for (int i = 0; i < nret; ++i)
        {
            SEXP v = PROTECT(luajr_tosexp(L, -nret + i));
            SET_VECTOR_ELT(retlist, i, v);
        }

        // Pop and return
        lua_pop(L, nret);
        UNPROTECT(1 + nret);
        return retlist;
    }
}

// Push copy of value at index of Lua state L to the stack for (different) Lua state dst.
extern "C" void luajr_xpush(lua_State* L, int index, lua_State* dst)
{
    if (L == dst)
        Rf_error("Cannot have L == dst in luajr_xpush.");

    switch (lua_type(L, index))
    {
        case LUA_TNIL:
            lua_pushnil(dst);
            break;

        case LUA_TBOOLEAN:
            lua_pushboolean(dst, lua_toboolean(L, index));
            break;

        case LUA_TLIGHTUSERDATA:
            lua_pushlightuserdata(dst, const_cast<void*>(lua_topointer(L, index)));
            break;

        case LUA_TNUMBER:
            lua_pushnumber(dst, lua_tonumber(L, index));
            break;

        case LUA_TSTRING:
        {
            size_t len;
            const char* s = lua_tolstring(L, index, &len);
            lua_pushlstring(dst, s, len);
            break;
        }

        case LUA_TTABLE:
        {
            index = abs_index(L, index);
            uint32_t asize, hsize;
            luajr_table_sizes(L, index, &asize, &hsize);
            lua_createtable(dst, asize, hsize);

            lua_pushnil(L);
            while (lua_next(L, index) != 0)
            {
                luajr_xpush(L, -2, dst);
                luajr_xpush(L, -1, dst);
                lua_rawset(dst, -3);
                lua_pop(L, 1);
            }
            break;
        }

        case LUA_TFUNCTION:
        {
            if (lua_iscfunction(L, index))
                Rf_error("luajr_xpush: cannot transfer C functions between states.");
            luaL_Buffer buf;
            luaL_buffinit(L, &buf);
            lua_pushvalue(L, index);
            if (lua_dump(L, [](lua_State*, const void* p, size_t sz, void* ud) -> int {
                    luaL_addlstring((luaL_Buffer*)ud, (const char*)p, sz);
                    return 0;
                }, &buf) != 0) {
                Rf_error("luajr_xpush: failed to dump function bytecode.");
            }
            lua_pop(L, 1);
            luaL_pushresult(&buf);
            size_t bc_len;
            const char* bc = lua_tolstring(L, -1, &bc_len);
            if (luaL_loadbuffer(dst, bc, bc_len, "xpush") != 0)
            {
                lua_pop(dst, 1);
                lua_pop(L, 1);
                Rf_error("luajr_xpush: failed to load function in target state.");
            }
            lua_pop(L, 1);
            break;
        }

        case LUA_TCDATA:
        {
            void* sexp = NULL;
            ptrdiff_t status = luajr_get_sexp_cdata(L, index, &sexp);
            if (status != -2)
            {
                if (sexp == NULL)
                    lua_pushnil(dst);
                else
                    luajr_pushsexp(dst, (SEXP)sexp, AC::value | AC::reference);
            }
            else
            {
                void* ptr = NULL;
                if (luajr_get_pointer_cdata(L, index, &ptr) == 0)
                    lua_pushlightuserdata(dst, ptr);
                else
                    Rf_error("luajr_xpush: cannot transfer cdata of this type to target state.");
            }
            break;
        }

        default:
            Rf_error("luajr_xpush: cannot transfer %s to another state.",
                lua_typename(L, lua_type(L, index)));
    }
}

// lua_CFunction: call an R function from Lua.
extern "C" int luajr_Rcall(lua_State* L)
{
    int nargs = lua_gettop(L) - 1;

    // First arg is R function as SEXP cdata
    SEXP f = NULL;
    if (luajr_get_sexp_cdata(L, 1, (void**)&f) != -1 || f == NULL)
        Rf_error("Rcall: first argument must be an R function SEXP.");

    // Build pairlist of args in reverse order
    SEXP call = R_NilValue;
    PROTECT_INDEX call_pi;
    R_ProtectWithIndex(call, &call_pi);

    for (int i = nargs + 1; i >= 2; i--)
    {
        SEXP arg = PROTECT(luajr_tosexp(L, i));
        R_Reprotect(call = Rf_cons(arg, call), call_pi);
        UNPROTECT(1);
    }

    // Prepend function to make the call
    R_Reprotect(call = Rf_lcons(f, call), call_pi);

    // Evaluate
    SEXP result = PROTECT(Rf_eval(call, R_GlobalEnv));
    luajr_pushsexp(L, result, AC::value);
    UNPROTECT(2);

    return 1;
}
