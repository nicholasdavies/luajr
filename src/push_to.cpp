// push_to.cpp: Move values between R and Lua

#include "shared.h"
#include <R.h>
#include <Rinternals.h>
#include <vector>
#include <string>
extern "C" {
#include "lua.h"
}

// Additional types specific to LuaJIT. From lj_obj.h.
#define LUA_TPROTO	(LUA_TTHREAD+1)
#define LUA_TCDATA	(LUA_TTHREAD+2)

// Helper function to push a vector to the Lua stack.
template <typename Push>
void push_R_vector(lua_State* L, SEXP x, char as, unsigned int len, Push push,
    bool can_simplify = true)
{
    unsigned int nrec = 0;

    // Get names of R object
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);
    if (names != R_NilValue && TYPEOF(names) != STRSXP)
        Rf_error("Non-character names attribute on vector.");

    if (can_simplify && as == 's' && len == 1)
    {
        // Primitive
        push(L, x, 0);
    }
    else if (as == 's' || as == 't')
    {
        // Table
        if (names != R_NilValue)
        {
            for (unsigned int i = 0; i < len; ++i)
                if (LENGTH(STRING_ELT(names, i)) > 0)
                    ++nrec;
        }
        lua_createtable(L, len - nrec, nrec);
        // This moves through the vector backwards so that if there are repeated
        // names, the earlier vector element with that name takes precedence.
        for (int i = len - 1; i >= 0; --i)
        {
            if (names != R_NilValue && LENGTH(STRING_ELT(names, i)) > 0)
            {
                lua_pushstring(L, CHAR(STRING_ELT(names, i)));
                push(L, x, i);
                lua_rawset(L, -3);
            }
            else
            {
                push(L, x, i);
                lua_rawseti(L, -2, i + 1);
            }
        }
    }
    else if (as == 'a')
    {
        // Array
        lua_createtable(L, len, 0);
        for (unsigned int i = 0; i < len; ++i)
        {
            push(L, x, i);
            lua_rawseti(L, -2, i + 1);
        }
    }
    else
    {
        Rf_error("Unrecognised args code %c for type %s.", as, Rf_type2char(TYPEOF(x)));
    }
}

// Analogous to Lua's lua_pushXXX(lua_State* L, XXX x) functions, this pushes
// the R object [x] onto Lua's stack.
// Supported: NILSXP, LGLSXP, INTSXP, REALSXP, STRSXP, VECSXP, EXTPTRSXP.
// Not supported: SYMSXP, LISTSXP, CLOSXP, ENVSXP, PROMSXP, LANGSXP, SPECIALSXP,
// BUILTINSXP, CHARSXP, CPLXSXP, DOTSXP, ANYSXP, EXPRSXP, BCODESXP, WEAKREFSXP,
// RAWSXP, S4SXP.
void luajr_pushsexp(lua_State* L, SEXP x, char as)
{
    // Get length of R object
    unsigned int len = Rf_length(x);

    if (len == 0)
    {
        // Length 0: always pass nil.
        lua_pushnil(L);
    }
    else switch (TYPEOF(x))
    {
        // Otherwise: switch on type...
        case NILSXP: // NULL
            lua_pushnil(L);
            break;
        case LGLSXP:
            push_R_vector(L, x, as, len,
                [](lua_State* L, SEXP x, unsigned int i)
                    { lua_pushboolean(L, LOGICAL_ELT(x, i)); });
            break;
        case INTSXP: // integer vectors: s, a, t
            push_R_vector(L, x, as, len,
                [](lua_State* L, SEXP x, unsigned int i)
                    { lua_pushinteger(L, INTEGER_ELT(x, i)); });
            break;
        case REALSXP: // numeric vectors: s, a, t
            push_R_vector(L, x, as, len,
                [](lua_State* L, SEXP x, unsigned int i)
                    { lua_pushnumber(L, REAL_ELT(x, i)); });
            break;
        case STRSXP: // character vectors: s, a, t
            push_R_vector(L, x, as, len,
                [](lua_State* L, SEXP x, unsigned int i)
                { lua_pushstring(L, CHAR(STRING_ELT(x, i))); });
            break;
        case VECSXP: // list (generic vector): s, a, t
            push_R_vector(L, x, as, len,
                [as](lua_State* L, SEXP x, unsigned int i)
                    { luajr_pushsexp(L, VECTOR_ELT(x, i), as); },
                false);
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
SEXP luajr_tosexp(lua_State* L, int index)
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
            SEXP retval;

            // Check if this is an R object table (i.e. has field __robj_ret_i)
            lua_getfield(L, index, "__robj_ret_i");
            if (!lua_isnil(L, -1))
            {
                // Value is R object table
                retval = VECTOR_ELT(Rf_findVar(RObjRetSymbol, R_GetCurrentEnv()), lua_tointeger(L, -1));
                lua_pop(L, 1); // from lua_getfield
            }
            else
            {
                // Value is a regular table: add each entry to a list
                lua_pop(L, 1); // from lua_getfield

                // Iterate through all entries, to later insert into a list.
                // TODO There is likely a better way of doing this
                std::vector<SEXP> arr;
                std::vector<SEXP> rec;
                std::vector<std::string> rec_names;

                lua_pushnil(L);
                while (lua_next(L, index) != 0)
                {
                    SEXP val = PROTECT(luajr_tosexp(L, -1));
                    if (lua_type(L, -2) == LUA_TNUMBER)
                    {
                        arr.push_back(val);
                    }
                    else if (lua_type(L, -2) == LUA_TSTRING)
                    {
                        rec.push_back(val);
                        rec_names.push_back(lua_tostring(L, -2));
                    }
                    else
                    {
                        Rf_error("Lua type %s keys cannot be represented in an R list.",
                            lua_typename(L, lua_type(L, -2)));
                    }
                    lua_pop(L, 1);
                }

                // Create list
                retval = PROTECT(Rf_allocVector3(VECSXP, arr.size() + rec.size(), NULL));
                for (unsigned int j = 0; j < arr.size(); ++j)
                    ((SEXP*)DATAPTR(retval))[j] = arr[j];
                for (unsigned int j = 0; j < rec.size(); ++j)
                    ((SEXP*)DATAPTR(retval))[arr.size() + j] = rec[j];

                // Set names
                if (!rec.empty())
                {
                    SEXP names = PROTECT(Rf_allocVector3(STRSXP, arr.size() + rec.size(), NULL));
                    for (unsigned int j = 0; j < arr.size(); ++j)
                        ((SEXP*)DATAPTR(names))[j] = R_BlankString;
                    for (unsigned int j = 0; j < rec.size(); ++j)
                        ((SEXP*)DATAPTR(names))[arr.size() + j] = Rf_mkChar(rec_names[j].c_str());
                    Rf_setAttrib(retval, R_NamesSymbol, names);
                    UNPROTECT(1);
                }

                // Return
                UNPROTECT(arr.size() + rec.size() + 1);
            }
            return retval;
        }
        case LUA_TLIGHTUSERDATA:
        case LUA_TFUNCTION:
        case LUA_TUSERDATA:
        case LUA_TTHREAD:
        case LUA_TPROTO:
        case LUA_TCDATA:
            return R_MakeExternalPtr(const_cast<void*>(lua_topointer(L, index)), R_NilValue, R_NilValue);
        default:
            Rf_error("Unknown return type detected: %d", lua_type(L, index));
    }
}

// Take a list of values passed from R and pass them to Lua
void R_pass_to_Lua(lua_State* L, SEXP args, const char* acode)
{
    unsigned int acode_length = std::strlen(acode);
    if (acode_length == 0)
        Rf_error("Length of args code is zero.");
    for (int i = 0; i < Rf_length(args); ++i)
        luajr_pushsexp(L, VECTOR_ELT(args, i), acode[i % acode_length]);
}

// Take values returned from Lua and return them to R
SEXP Lua_return_to_R(lua_State* L, int nret)
{
    // No return value: return NULL
    if (nret == 0)
    {
        return R_NilValue;
    }
    else if (nret == 1)
    {
        // One return value: convert to SEXP, pop, and return
        SEXP retval = luajr_tosexp(L, -1);
        lua_pop(L, 1);
        return retval;
    }
    else
    {
        // Multiple return values: return as list
        SEXP retlist = PROTECT(Rf_allocVector3(VECSXP, nret, NULL));

        // Add elements to table (popping from top of stack)
        for (int i = 0; i < nret; ++i)
        {
            SEXP v = PROTECT(luajr_tosexp(L, -nret + i));
            SET_VECTOR_ELT(retlist, i, v);
        }

        lua_pop(L, nret);
        UNPROTECT(1 + nret);
        return retlist;
    }
}

