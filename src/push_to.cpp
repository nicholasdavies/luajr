// push_to.cpp: Move values between R and Lua

#include "shared.h"
#include "registry_entry.h"
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
            if (STRING_ELT(x, i) == R_NaString)
                lua_pushnil(L);
            else
            {
                R_xlen_t xlen = Rf_xlength(STRING_ELT(x, i));
                if (xlen >= LJ_MAX_STR)
                    luajr_error(L, "Cannot pass string with more than %d bytes. Requested size: %.0f.", LJ_MAX_STR, (double)xlen);
                lua_pushstring(L, CHAR(STRING_ELT(x, i)));
            }
            break;
        default:
            lua_pushnil(L);
            break;
    }
}

// Push an R atomic or VECSXP vector as a Lua table with names.
// Unnamed elements get sequential integer keys as in Lua.
// For duplicate names, later entries win, also as in Lua.
static void push_as_table(lua_State* L, SEXP x)
{
    // Get length of vector
    R_xlen_t xlen = Rf_xlength(x);
    if (xlen >= LJ_MAX_ASIZE || xlen >= std::numeric_limits<int>::max())
        luajr_error(L, "List is too large to be passed to Lua. Cannot create Lua table with more than %d elements. Requested size: %.0f.",
            LJ_MAX_ASIZE - 1, (double)xlen);
    int len = Rf_length(x);

    // Get names of list elements
    // NOTE: The PROTECT call here isn't needed, except to prevent rchk from
    // issuing a false-positive warning.
    SEXP names = PROTECT(Rf_getAttrib(x, R_NamesSymbol));
    if (names != R_NilValue && TYPEOF(names) != STRSXP)
        luajr_error(L, "Non-character names attribute on vector.");

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

    // Push all elements
    int sxptype = TYPEOF(x);
    int arr_i = 1;
    for (int i = 0; i < len; ++i)
    {
        // Push the element
        if (sxptype == VECSXP)
            luajr_pushsexp(L, VECTOR_ELT(x, i), AC::value | AC::native);
        else
            push_native_element(L, x, sxptype, i);

        // Assign to string key or sequential integer key
        if (names != R_NilValue && LENGTH(STRING_ELT(names, i)) > 0)
        {
            lua_pushstring(L, CHAR(STRING_ELT(names, i)));
            lua_insert(L, -2); // swap key and value for lua_rawset
            lua_rawset(L, -3);
        }
        else
        {
            lua_rawseti(L, -2, arr_i++);
        }
    }

    UNPROTECT(1);
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
            luajr_error(L, "NULL passed where a value was required (strict argcode).");
        if (is_native)
            lua_pushnil(L);
        else
            luajr_internal_pushsexp(L, (void*)R_NilValue);
        return;
    }

    switch (type)
    {
        // auto / .
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
                case EXTPTRSXP:  specific = AC::pointer; break;
                default:         specific = AC::sexp; break;
            }
            if (is_native && Rf_xlength(x) > 1)
                luajr_pushsexp(L, x, AC::native | AC::list);
            else
                luajr_pushsexp(L, x, (as & ~AC::type_mask) | specific);
            break;
        }

        // sexp / S
        case AC::sexp:
            luajr_internal_pushsexp(L, (void*)x);
            break;

        // symbol, pairlist: not implemented

        // function / rfunction / F
        case AC::function:
            if (is_native)
            {
                if (TYPEOF(x) == CLOSXP || TYPEOF(x) == SPECIALSXP || TYPEOF(x) == BUILTINSXP)
                {
                    // R function: push luajr.rfunction cdata as upvalue of a C
                    // closure that calls it. The cdata's __gc releases on GC.
                    R_PreserveObject(x);
                    luajr_internal_pushrfunction(L, (void*)x);
                    lua_pushcclosure(L, [](lua_State* L) -> int {
                        int n = lua_gettop(L);
                        lua_pushvalue(L, lua_upvalueindex(1));
                        lua_insert(L, 1);
                        lua_call(L, n, LUA_MULTRET);
                        return lua_gettop(L);
                    }, 1);
                }
                else if (TYPEOF(x) == EXTPTRSXP)
                {
                    // External pointer wrapping a Lua function: push it directly.
                    luajr_pushfunc(x);
                }
                else
                {
                    luajr_error(L, "Expected R or Lua function, got %s.", Rf_type2char(TYPEOF(x)));
                }
            }
            else
            {
                if (TYPEOF(x) != CLOSXP && TYPEOF(x) != SPECIALSXP && TYPEOF(x) != BUILTINSXP)
                    luajr_error(L, "Expected function, got %s.", Rf_type2char(TYPEOF(x)));
                R_PreserveObject(x);
                luajr_internal_pushrfunction(L, (void*)x);
            }
            break;

        // environment / E
        case AC::environment:
            if (TYPEOF(x) != ENVSXP)
                luajr_error(L, "Expected environment, got %s.", Rf_type2char(TYPEOF(x)));
            R_PreserveObject(x);
            luajr_internal_pushenvironment(L, (void*)x);
            break;

        // language: not implemented

        // logical / L, integer / I, numeric / N, (complex / Z not implemented), character / C
        case AC::logical:
        case AC::integer:
        case AC::numeric:
        case AC::character:
        {
            int expected;
            switch (type) {
                case AC::logical:   expected = LGLSXP;  break;
                case AC::integer:   expected = INTSXP;  break;
                case AC::numeric:   expected = REALSXP; break;
                case AC::character: expected = STRSXP;  break;
                default:            expected = 0;       break; // unreachable
            }
            int actual = TYPEOF(x);

            // Coercion (unless strict): integer <-> numeric
            bool coerced = false;
            if (actual != expected && !is_strict && !is_ref)
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
                luajr_error(L, "Expected %s, got %s.", Rf_type2char(expected), Rf_type2char(actual));

            if (is_native)
            {
                R_xlen_t xlen = Rf_xlength(x);
                if (xlen == 0)
                    lua_pushnil(L);
                else if (xlen != 1)
                    luajr_error(L, "Expected scalar (length 1), got length %.0f.", (double)xlen);
                else
                    push_native_element(L, x, actual, 0);
            }
            else
            {
                double c_val = is_ref ? -1.0 : -2.0;
                void* p;
                switch (actual) {
                    case LGLSXP:  p = (void*)(LOGICAL(x) - 1); break;
                    case INTSXP:  p = (void*)(INTEGER(x) - 1); break;
                    case REALSXP: p = (void*)(REAL(x) - 1); break;
                    case STRSXP:  p = (void*)(STRING_PTR_RO(x) - 1); break;
                    default:      p = nullptr; break;
                }
                if (!is_ref)
                    R_PreserveObject(x);
                luajr_internal_pushvector(L, actual, p, (void*)x, (double)Rf_xlength(x), c_val);
            }

            if (coerced)
                UNPROTECT(1);
            break;
        }

        // list / V
        case AC::list:
            if (is_native)
            {
                push_as_table(L, x);
            }
            else
            {
                if (TYPEOF(x) != VECSXP)
                    luajr_error(L, "Expected list, got %s.", Rf_type2char(TYPEOF(x)));
                double c_val = is_ref ? -1.0 : -2.0;
                if (!is_ref)
                    R_PreserveObject(x);
                luajr_internal_pushvector(L, VECSXP,
                    (void*)(const_cast<SEXP*>((const SEXP*)DATAPTR_RO(x)) - 1),
                    (void*)x, (double)Rf_xlength(x), c_val);
            }
            break;

        // expression, raw: not implemented

        // pointer / P
        case AC::pointer:
            if (TYPEOF(x) != EXTPTRSXP)
                luajr_error(L, "Expected external pointer, got %s.", Rf_type2char(TYPEOF(x)));
            lua_pushlightuserdata(L, R_ExternalPtrAddr(x));
            break;

        default:
            luajr_error(L, "Unrecognised argcode type %d.", type);
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
                    luajr_popstop(L, 2, "Lua type %s keys cannot be represented in an R list.",
                        lua_typename(L, lua_type(L, -2)));
                lua_pop(L, 1);
            }

            if (narr + nrec >= LJ_MAX_ASIZE)
                luajr_error(L, "Table is too large to be returned to R. Limit is %d elements. Requested size: %.0f.",
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
            ptrdiff_t status = luajr_internal_tosexp(L, index, (void**)&s);
            if (status == -2)
                luajr_error(L, "Cannot return cdata of this type to R.");
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
            luajr_error(L, "Unknown return type detected: %d", lua_type(L, index));
    }
}

// lua_CFunction: luajr_tosexp wrapper.
// Args: (1) any Lua value. Returns: SEXP cdata.
// Note: returned SEXP may be unprotected (e.g. fresh ScalarReal). The caller
// must consume immediately or PROTECT it.
extern "C" int luajr_tosexp_cf(lua_State* L)
{
    SEXP s = luajr_tosexp(L, 1);
    luajr_internal_pushsexp(L, (void*)s);
    return 1;
}

// lua_CFunction: luajr_pushsexp wrapper.
// Args: (1) SEXP cdata, (2) optional argcode byte (default AC::value).
extern "C" int luajr_fromsexp_cf(lua_State* L)
{
    SEXP s = NULL;
    if (luajr_internal_tosexp(L, 1, (void**)&s) == -2)
        luajr_error(L, "luajr.from_sexp: first argument must be a SEXP cdata.");
    if (s == NULL)
        s = R_NilValue;

    unsigned char as = AC::value;
    if (!lua_isnoneornil(L, 2))
        as = (unsigned char)lua_tointeger(L, 2);

    luajr_pushsexp(L, s, as);
    return 1;
}

// Take a list of values passed from R and pass them to Lua
// Specifically, push each of the elements of the list args onto the stack of
// L, using the args code in acode.
extern "C" void luajr_pass(lua_State* L, SEXP args, SEXP acode)
{
    int acode_length = Rf_length(acode);
    if (acode_length == 0)
        luajr_error(L, "Length of args code is zero.");
    const unsigned char* ac = RAW(acode);
    for (int i = 0; i < Rf_length(args); ++i)
        luajr_pushsexp(L, VECTOR_ELT(args, i), ac[i < acode_length ? i : acode_length - 1]);
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
        luajr_error(L, "Cannot have L == dst in luajr_xpush.");

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
            luajr_internal_tablesize(L, index, &asize, &hsize);
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
                luajr_error(L, "luajr_xpush: cannot transfer C functions between states.");
            luaL_Buffer buf;
            luaL_buffinit(L, &buf);
            lua_pushvalue(L, index);
            if (lua_dump(L, [](lua_State*, const void* p, size_t sz, void* ud) -> int {
                    luaL_addlstring((luaL_Buffer*)ud, (const char*)p, sz);
                    return 0;
                }, &buf) != 0) {
                luajr_error(L, "luajr_xpush: failed to dump function bytecode.");
            }
            lua_pop(L, 1);
            luaL_pushresult(&buf);
            size_t bc_len;
            const char* bc = lua_tolstring(L, -1, &bc_len);
            if (luaL_loadbuffer(dst, bc, bc_len, "xpush") != 0)
            {
                lua_pop(dst, 1);
                lua_pop(L, 1);
                luajr_error(L, "luajr_xpush: failed to load function in target state.");
            }
            lua_pop(L, 1);
            break;
        }

        case LUA_TCDATA:
        {
            void* sexp = NULL;
            ptrdiff_t status = luajr_internal_tosexp(L, index, &sexp);
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
                if (luajr_internal_topointer(L, index, &ptr) == 0)
                    lua_pushlightuserdata(dst, ptr);
                else
                    luajr_error(L, "luajr_xpush: cannot transfer cdata of this type to target state.");
            }
            break;
        }

        default:
            luajr_error(L, "luajr_xpush: cannot transfer %s to another state.",
                lua_typename(L, lua_type(L, index)));
    }
}

// lua_CFunction: call an R function from Lua.
// Lua args: (rfunc_sexp, args_table, env_or_nil).
//   args_table: integer keys (1..#t) become positional args (in numeric order);
//               string keys become named args (tagged in the pairlist).
//   env_or_nil: optional ENVSXP for evaluation; defaults to R_GlobalEnv.
extern "C" int luajr_rcall_cf(lua_State* L)
{
    // Arg 1: R function as SEXP cdata
    SEXP f = NULL;
    if (luajr_internal_tosexp(L, 1, (void**)&f) != -1 || f == NULL)
        luajr_error(L, "rcall: first argument must be an R function SEXP.");

    // Arg 2: args table
    if (!lua_istable(L, 2))
        luajr_error(L, "rcall: second argument must be a table of args.");

    // Arg 3: optional environment
    SEXP env = R_GlobalEnv;
    if (!lua_isnoneornil(L, 3))
    {
        SEXP env_sexp = NULL;
        if (luajr_internal_tosexp(L, 3, (void**)&env_sexp) != -1 || env_sexp == NULL || TYPEOF(env_sexp) != ENVSXP)
            luajr_error(L, "rcall: third argument must be an environment.");
        env = env_sexp;
    }

    // Build positional pairlist from integer keys 1..#t in reverse so cons builds in forward order
    SEXP call = R_NilValue;
    PROTECT_INDEX call_pi;
    R_ProtectWithIndex(call, &call_pi);

    int narr = lua_objlen(L, 2);
    for (int i = narr; i >= 1; --i)
    {
        lua_rawgeti(L, 2, i);
        SEXP arg = PROTECT(luajr_tosexp(L, -1));
        R_Reprotect(call = Rf_cons(arg, call), call_pi);
        UNPROTECT(1);
        lua_pop(L, 1);
    }

    // Walk the args table: handle named args, validate that any integer keys
    // are in [1, narr], and reject any other key type
    SEXP tail = call;
    if (tail != R_NilValue)
        while (CDR(tail) != R_NilValue) tail = CDR(tail);
    lua_pushnil(L);
    while (lua_next(L, 2) != 0)
    {
        int kt = lua_type(L, -2);
        if (kt == LUA_TSTRING)
        {
            SEXP arg = PROTECT(luajr_tosexp(L, -1));
            SEXP node = PROTECT(Rf_cons(arg, R_NilValue));
            SET_TAG(node, Rf_install(lua_tostring(L, -2)));
            if (call == R_NilValue)
                R_Reprotect(call = node, call_pi);
            else
                SETCDR(tail, node);
            tail = node;
            UNPROTECT(2);
        }
        else if (kt == LUA_TNUMBER)
        {
            lua_Number k = lua_tonumber(L, -2);
            int ki = k;
            if (k != ki || ki < 1 || ki > narr)
                luajr_popstop(L, 2, "rcall: integer key %g in args table must be in [1, %d]", (double)k, narr);
        }
        else
            luajr_popstop(L, 2, "rcall: invalid key type %s in args table", lua_typename(L, kt));
        lua_pop(L, 1);
    }

    // Prepend function to make the call
    R_Reprotect(call = Rf_lcons(f, call), call_pi);

    // Evaluate
    SEXP result = PROTECT(Rf_eval(call, env));
    luajr_pushsexp(L, result, AC::value);
    UNPROTECT(2);

    return 1;
}
