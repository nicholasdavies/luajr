#include "shared.h"
#include <Rcpp.h>
extern "C" {
#include "lua.h"
}

// Additional types specific to LuaJIT. From lj_obj.h.
#define LUA_TPROTO	(LUA_TTHREAD+1)
#define LUA_TCDATA	(LUA_TTHREAD+2)

// Helper function to push a 'primitive vector' (LGLSXP, INTSXP, REALSXP,
// STRSXP) to the Lua stack.
template <typename Push>
void push_R_vector(lua_State* L, SEXP x, char as, unsigned int len, Push push,
    bool can_simplify = true)
{
    unsigned int nrec = 0;

    // Get names of R object
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);

    // TODO edge cases to handle: repeated names; NA names; non-character names
    //  - repeated names is handled bc only R lists maintain names so all sublists will
    // be available as 0/1/2 indices and otherwise only the first/last should apply
    // (to be consistent with R, only the first??
    //  - NA name, this gets converted to NA so it is fine
    //  - non-character names, error

    // Warn about names
    // TODO handle this better; I think the decision in devnotes.txt is to always strip array passes
    if (names != R_NilValue)
        Rcpp::warning("An R object with names has been passed to Lua. Lua does not preserve a given order of items in a table.");

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
        for (unsigned int i = 0; i < len; ++i)
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
        Rcpp::stop("Unrecognised args code ", as, " for type ", Rf_type2char(TYPEOF(x)));
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
            lua_pushlightuserdata(L, Rcpp::as<void*>(x));
            break;
        default:
            Rcpp::stop("Cannot convert %s to Lua.", Rf_type2char(TYPEOF(x)));
    }
}

// Analogous to Lua's lua_toXXX(lua_State* L, int index) functions, this gets
// the value at [index] on the stack as a SEXP that can be handed to R.
SEXP luajr_tosexp(lua_State* L, int index)
{
    // Convert index to absolute index
    index = (index > 0 || index <= LUA_REGISTRYINDEX) ? index : lua_gettop(L) + index + 1;

    // Depending on the Lua type of the value at Lua stack index [index], set
    // retval to the corresponding R type and value.
    SEXP retval;
    switch (lua_type(L, index))
    {
        case LUA_TNIL:
            retval = R_NilValue;
            break;
        case LUA_TBOOLEAN:
            retval = Rcpp::wrap<bool>(lua_toboolean(L, index));
            break;
        case LUA_TNUMBER:
            retval = Rcpp::wrap<double>(lua_tonumber(L, index));
            break;
        case LUA_TSTRING:
            retval = Rcpp::wrap<std::string>(lua_tostring(L, index));
            break;
        case LUA_TTABLE:
        {
            // Check if this is an R object table (i.e. has field __robj_ret_i)
            lua_getfield(L, index, "__robj_ret_i");
            if (!lua_isnil(L, -1))
            {
                // Value is R object table
                retval = VECTOR_ELT(Rf_findVar(RObjRetSymbol, R_GetCurrentEnv()), lua_tointeger(L, -1));
                lua_pop(L, 1);
            }
            else
            {
                // Value is a regular table: add each entry to a list
                lua_pop(L, 1);
                Rcpp::List list;
                lua_pushnil(L);
                while (lua_next(L, index) != 0) {
                    SEXP val = luajr_tosexp(L, -1);
                    if (lua_type(L, -2) == LUA_TNUMBER)
                        list.insert(lua_tointeger(L, -2) - 1, val);
                    else if (lua_type(L, -2) == LUA_TSTRING)
                        list.push_back(val, lua_tostring(L, -2));
                    else
                        Rcpp::stop("Non-number, non-string table keys cannot be represented in an R list.");
                    lua_pop(L, 1);
                }
                retval = list;
            }
            break;
        }
        case LUA_TLIGHTUSERDATA:
        case LUA_TFUNCTION:
        case LUA_TUSERDATA:
        case LUA_TTHREAD:
        case LUA_TPROTO:
        case LUA_TCDATA:
            retval = Rcpp::XPtr<int>(reinterpret_cast<int*>(const_cast<void*>(lua_topointer(L, index))), false);
            break;
        default:
            Rcpp::stop("Unknown return type detected: %d", lua_type(L, index));
            break;
    }

    // Return the set return value as an R object.
    return retval;
}
