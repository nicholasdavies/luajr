// push_to.cpp: Move values between R and Lua

#include "shared.h"
#include <vector>
#include <string>
extern "C" {
#include "lua.h"
}
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// Additional types specific to LuaJIT. From lj_obj.h.
#define LUA_TPROTO	(LUA_TTHREAD+1)
#define LUA_TCDATA	(LUA_TTHREAD+2)

// Helper function to push a vector to the Lua stack.
template <typename Push>
static void push_R_vector(lua_State* L, SEXP x, char as, int type, Push push)
{
    // Get length of vector
    int len = Rf_length(x);

    switch (as)
    {
        case 'r':
            // Get luajr.construct_ref() on the stack
            lua_pushlightuserdata(L, (void*)&luajr_construct_ref);
            lua_rawget(L, LUA_REGISTRYINDEX);
            // Call it with arguments x as userdata, type code as integer
            lua_pushlightuserdata(L, x);
            lua_pushinteger(L, type | REFERENCE_T);
            luajr_pcall(L, 2, 1, "luajr.construct_ref() from push_R_vector()");
            break;

        case 'v':
            // Get luajr.construct_vec() on the stack
            lua_pushlightuserdata(L, (void*)&luajr_construct_vec);
            lua_rawget(L, LUA_REGISTRYINDEX);
            // Call it with arguments x as userdata, type code as integer
            lua_pushlightuserdata(L, x);
            lua_pushinteger(L, type | VECTOR_T);
            luajr_pcall(L, 2, 1, "luajr.construct_vec() from push_R_vector()");
            break;

        case 's':
        case 'a':
            if (len == 0)
                lua_pushnil(L); // Length 0: push nil
            else if (len == 1 && as == 's')
                push(L, x, 0);  // Length 1 and 's': push scalar
            else
            {                   // Length >1 or 'a': push table
                lua_createtable(L, len, 0);
                for (int i = 0; i < len; ++i)
                {
                    push(L, x, i);
                    lua_rawseti(L, -2, i + 1);
                }
            }
            break;

        default:
            if (as >= '1' && as <= '9')
            {
                int reqn = as - '0';
                if (len != reqn)
                    Rf_error("Vector of length %d requested, but passed vector of length %d.", reqn, len);
                push_R_vector(L, x, 's', type, push);
                break;
            }
            Rf_error("Unrecognised args code %c for type %s.", as, Rf_type2char(TYPEOF(x)));
            break;
    }
}

// Helper function to push a list to the Lua stack.
static void push_R_list(lua_State* L, SEXP x, char as)
{
    // Get length of vector
    int len = Rf_length(x);

    // Get names of list elements
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);
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

    switch (as)
    {
        case 'r':
        case 'v':
            // Get luajr.construct_list on the stack
            lua_pushlightuserdata(L, (void*)&luajr_construct_list);
            lua_rawget(L, LUA_REGISTRYINDEX);

            // Push two arguments for luajr.construct_list:
            // 1. A table containing all elements of the list.
            lua_createtable(L, len, 0);

            // Add each element to table in turn
            for (int i = 0; i < len; ++i)
            {
                luajr_pushsexp(L, VECTOR_ELT(x, i), as);
                lua_rawseti(L, -2, i + 1);
            }

            // 2. A table with mappings from names to integer keys
            lua_createtable(L, 0, n_named);

            // Add each name
            if (names != R_NilValue)
            {
                for (int i = 0; i < len; ++i)
                {
                    if (LENGTH(STRING_ELT(names, i)) > 0)
                    {
                        lua_pushstring(L, CHAR(STRING_ELT(names, i)));
                        lua_pushinteger(L, i + 1);
                        lua_rawset(L, -3);
                    }
                }
            }

            // Call luajr.construct_list
            luajr_pcall(L, 2, 1, "luajr.construct_list() from push_R_list()");

            break;

        case 's':
            // Create a table on the stack with len elements, len - n_named of
            // which are 'arr' elements and n_named of which are 'rec' elements.
            lua_createtable(L, len - n_named, n_named);

            // This moves through the vector backwards so that if there are repeated
            // names, the earlier vector element with that name takes precedence.
            for (int i = len - 1; i >= 0; --i)
            {
                if (names != R_NilValue && LENGTH(STRING_ELT(names, i)) > 0)
                {
                    // Add string-indexed alias of this element
                    lua_pushstring(L, CHAR(STRING_ELT(names, i)));
                    luajr_pushsexp(L, VECTOR_ELT(x, i), as);
                    lua_rawset(L, -3);
                }
                else
                {
                    // Add integer-indexed alias of this element
                    luajr_pushsexp(L, VECTOR_ELT(x, i), as);
                    lua_rawseti(L, -2, i + 1);
                }
            }
            break;

        default:
            Rf_error("Unrecognised args code %c for type %s.", as, Rf_type2char(TYPEOF(x)));
            break;
    }
}

// Analogous to Lua's lua_pushXXX(lua_State* L, XXX x) functions, this pushes
// the R object [x] onto Lua's stack.
// Supported: NILSXP, LGLSXP, INTSXP, REALSXP, STRSXP, VECSXP, EXTPTRSXP.
// Not supported: SYMSXP, LISTSXP, CLOSXP, ENVSXP, PROMSXP, LANGSXP, SPECIALSXP,
// BUILTINSXP, CHARSXP, CPLXSXP, DOTSXP, ANYSXP, EXPRSXP, BCODESXP, WEAKREFSXP,
// RAWSXP, S4SXP.
extern "C" void luajr_pushsexp(lua_State* L, SEXP x, char as)
{
    switch (TYPEOF(x))
    {
        case NILSXP: // NULL
            if (as == 'r' || as == 'v')
            {
                lua_pushlightuserdata(L, (void*)&luajr_construct_null);
                lua_rawget(L, LUA_REGISTRYINDEX);
                luajr_pcall(L, 0, 1, "luajr.construct_null() from luajr_pushsexp()");
            }
            else
                lua_pushnil(L);
            break;
        case LGLSXP: // logical vector: r, v, s, a, 1-9
            push_R_vector(L, x, as, LOGICAL_T,
                [](lua_State* L, SEXP x, unsigned int i)
                    { lua_pushboolean(L, LOGICAL_ELT(x, i)); });
            break;
        case INTSXP: // integer vector: r, v, s, a, 1-9
            push_R_vector(L, x, as, INTEGER_T,
                [](lua_State* L, SEXP x, unsigned int i)
                    { lua_pushinteger(L, INTEGER_ELT(x, i)); });
            break;
        case REALSXP: // numeric vector: r, v, s, a, 1-9
            push_R_vector(L, x, as, NUMERIC_T,
                [](lua_State* L, SEXP x, unsigned int i)
                    { lua_pushnumber(L, REAL_ELT(x, i)); });
            break;
        case STRSXP: // character vector: r, v, s, a, 1-9
            push_R_vector(L, x, as, CHARACTER_T,
                [](lua_State* L, SEXP x, unsigned int i)
                    { lua_pushstring(L, CHAR(STRING_ELT(x, i))); });
            break;
        case VECSXP: // list (generic vector): r, v, s
            push_R_list(L, x, as);
            break;
        case EXTPTRSXP: // external pointer
            lua_pushlightuserdata(L, R_ExternalPtrAddr(x));
            break;
        default:
            Rf_error("Cannot convert %s to Lua.", Rf_type2char(TYPEOF(x)));
    }
}

// Analogous to Lua's lua_toXXX(lua_State* L, int index) functions, this gets
// the value at [index] on the stack as a SEXP that can be handed to R. Note
// that SEXPs returned from this function need to be protected in calling code.
extern "C" SEXP luajr_tosexp(lua_State* L, int index)
{
    // Convert index to absolute index
    index = (index > 0 || index <= LUA_REGISTRYINDEX) ? index : lua_gettop(L) + index + 1;

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
            return Rf_mkString(lua_tostring(L, index));
        case LUA_TTABLE:
        {
            // Get luajr.return_info() on the stack
            lua_pushlightuserdata(L, (void*)&luajr_return_info);
            lua_rawget(L, LUA_REGISTRYINDEX);

            // Call it with table arg
            lua_pushvalue(L, index);
            luajr_pcall(L, 1, 2, "luajr.return_info() from luajr_tosexp() [1]");

            // If not a known table type, return normal table
            if (lua_isnil(L, -2))
            {
                // Add each entry to a list
                lua_pop(L, 2); // clear two return values

                // First pass: count table entries of each type.
                int narr = 0, nrec = 0;
                lua_pushnil(L);
                while (lua_next(L, index) != 0)
                {
                    if      (lua_type(L, -2) == LUA_TNUMBER) ++narr;
                    else if (lua_type(L, -2) == LUA_TSTRING) ++nrec;
                    else    Rf_error("Lua type %s keys cannot be represented in an R list.", lua_typename(L, lua_type(L, -2)));
                    lua_pop(L, 1);
                }

                // Create list and names
                SEXP retval = PROTECT(Rf_allocVector3(VECSXP, narr + nrec, NULL));
                SEXP names = R_NilValue;
                if (nrec > 0)
                    names = PROTECT(Rf_allocVector3(STRSXP, narr + nrec, NULL));

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
                }

                // Name and return
                Rf_setAttrib(retval, R_NamesSymbol, names);
                UNPROTECT(1 + (nrec > 0) + narr + nrec);
                return retval;
            }

            // If is a known table type
            int type = lua_tointeger(L, -2);
            R_xlen_t size = lua_tonumber(L, -1);
            lua_pop(L, 2);

            // List type
            if (type == LIST_T)
            {
                // Add each entry to a list
                SEXP retval = PROTECT(Rf_allocVector3(VECSXP, size, NULL));
                int nprotect = 1;

                // Get the list contents on the stack
                lua_rawgeti(L, index, 0); // get list[0]

                // Put all entries into the list
                lua_pushnil(L);
                while (lua_next(L, -2) != 0)
                {
                    SEXP val = PROTECT(luajr_tosexp(L, -1));
                    ++nprotect;
                    if (lua_type(L, -2) == LUA_TNUMBER) // List element
                    {
                        SET_VECTOR_ELT(retval, lua_tointeger(L, -2) - 1, val);
                    }
                    else if (lua_type(L, -2) == LUA_TSTRING) // Attribute
                    {
                        const char* attr_name = lua_tostring(L, -2);
                        if (std::strcmp(attr_name, "names") == 0) // Special behaviour for names attribute
                        {
                            if (size > 0)
                            {
                                SEXP names = PROTECT(Rf_allocVector3(STRSXP, size, NULL));
                                ++nprotect;
                                SEXP setnames = Rf_getAttrib(val, R_NamesSymbol);
                                for (int i = 0; i < Rf_length(val); ++i) {
                                    int index = REAL(VECTOR_ELT(val, i))[0] - 1;
                                    SEXP name = STRING_ELT(setnames, i);
                                    SET_STRING_ELT(names, index, name);
                                }
                                Rf_setAttrib(retval, R_NamesSymbol, names);
                            }
                        }
                        else
                        {
                            Rf_setAttrib(retval, Rf_install(attr_name), val);
                        }
                    }
                    else
                    {
                        Rf_error("Lua type %s keys cannot be represented in an R list.",
                            lua_typename(L, lua_type(L, -2)));
                    }
                    lua_pop(L, 1);
                }

                // Special check: ensure data.frame has rownames attribute
                // If retval is data.frame with at least one column, but no row names:
                if (Rf_inherits(retval, "data.frame") && Rf_length(retval) > 0 &&
                    Rf_getAttrib(retval, R_RowNamesSymbol) == R_NilValue)
                {
                    // R has a special shorthand for "short" rownames: c(NA_integer_, nrow) (see attrib.c)
                    // TODO This will fail if the number of rows is 2^31 or higher. However, it also seems
                    // that R itself cannot really handle such long data.frames (at least as of R 4.3.2).
                    SEXP rownames = PROTECT(Rf_allocVector3(INTSXP, 2, NULL));
                    ++nprotect;
                    INTEGER(rownames)[0] = NA_INTEGER;
                    INTEGER(rownames)[1] = Rf_length(VECTOR_ELT(retval, 0));
                    Rf_setAttrib(retval, R_RowNamesSymbol, rownames);
                }

                // Return
                lua_pop(L, 1); // pop list[0]
                UNPROTECT(nprotect);
                return retval;
            }

            // Other known table type
            int rtype = NILSXP;
            if (type == (CHARACTER_T | VECTOR_T))
                rtype = STRSXP;
            else
                Rf_error("Unknown type");

            SEXP ret = PROTECT(Rf_allocVector3(rtype, size, NULL));
            // Now get luajr.return_copy() on the stack
            lua_pushlightuserdata(L, (void*)&luajr_return_copy);
            lua_rawget(L, LUA_REGISTRYINDEX);
            // Call it with cdata arg and pointer
            lua_pushvalue(L, index);
            lua_pushlightuserdata(L, ret);
            luajr_pcall(L, 2, 0, "luajr.return_copy() from luajr_tosexp() [1]");
            // Return SEXP
            UNPROTECT(1);
            return ret;
        }
        case LUA_TLIGHTUSERDATA:
        case LUA_TFUNCTION:
        case LUA_TUSERDATA:
        case LUA_TTHREAD:
        case LUA_TPROTO:
            return R_MakeExternalPtr(const_cast<void*>(lua_topointer(L, index)), R_NilValue, R_NilValue);
        case LUA_TCDATA:
        {
            // Get luajr.return_info() on the stack
            lua_pushlightuserdata(L, (void*)&luajr_return_info);
            lua_rawget(L, LUA_REGISTRYINDEX);
            // Call it with cdata arg
            lua_pushvalue(L, index);
            luajr_pcall(L, 1, 2, "luajr.return_info() from luajr_tosexp() [2]");

            // If not a known cdata type, return external pointer
            if (lua_isnil(L, -2))
                return R_MakeExternalPtr(const_cast<void*>(lua_topointer(L, index)), R_NilValue, R_NilValue);

            // If is a known cdata type
            int type = lua_tointeger(L, -2);
            if (type < VECTOR_T)
            {
                // Reference type
                lua_pop(L, 2);

                SEXP ret = R_NilValue;
                // Get luajr.return_copy() on the stack
                lua_pushlightuserdata(L, (void*)&luajr_return_copy);
                lua_rawget(L, LUA_REGISTRYINDEX);
                // Call it with cdata arg and sexp
                lua_pushvalue(L, index);
                lua_pushlightuserdata(L, &ret);
                luajr_pcall(L, 2, 0, "luajr.return_copy() from luajr_tosexp() [2]");
                // Return SEXP
                return ret;
            }
            else if (type == NULL_T)
            {
                lua_pop(L, 2);
                return R_NilValue;
            }
            else
            {
                // Value type
                R_xlen_t size = lua_tonumber(L, -1);
                lua_pop(L, 2);

                int rtype = NILSXP;
                if      (type == (LOGICAL_T | VECTOR_T))    rtype = LGLSXP;
                else if (type == (INTEGER_T | VECTOR_T))    rtype = INTSXP;
                else if (type == (NUMERIC_T | VECTOR_T))    rtype = REALSXP;
                else Rf_error("Unknown type");

                SEXP ret = PROTECT(Rf_allocVector3(rtype, size, NULL));
                // Now get luajr.return_copy() on the stack
                lua_pushlightuserdata(L, (void*)&luajr_return_copy);
                lua_rawget(L, LUA_REGISTRYINDEX);
                // Call it with cdata arg and pointer
                lua_pushvalue(L, index);
                lua_pushlightuserdata(L, DATAPTR(ret));
                luajr_pcall(L, 2, 0, "luajr.return_copy() from luajr_tosexp() [3]");
                // Return SEXP
                UNPROTECT(1);
                return ret;
            }
        }
        default:
            Rf_error("Unknown return type detected: %d", lua_type(L, index));
    }
}

// Take a list of values passed from R and pass them to Lua
// Specifically, push each of the elements of the list args onto the stack of
// L, using the args code in acode.
extern "C" void luajr_pass(lua_State* L, SEXP args, const char* acode)
{
    unsigned int acode_length = std::strlen(acode);
    if (acode_length == 0)
        Rf_error("Length of args code is zero.");
    for (int i = 0; i < Rf_length(args); ++i)
        luajr_pushsexp(L, VECTOR_ELT(args, i), acode[i % acode_length]);
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
        SEXP retlist = PROTECT(Rf_allocVector3(VECSXP, nret, NULL));

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
