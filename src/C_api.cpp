#include "shared.h"

// Additional types specific to LuaJIT. From lj_obj.h.
#define LUA_TPROTO	(LUA_TTHREAD+1)
#define LUA_TCDATA	(LUA_TTHREAD+2)

// Analogous to Lua's lua_pushXXX(lua_State* L, XXX x) functions, this pushes
// the R object [x] onto Lua's stack.
// TODO this needs to be able to handle vectors...
void luajr_pushsexp(lua_State* L, SEXP x, char as)
{
    // Get length of R object
    unsigned int len = Rf_length(x);
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);
    unsigned int nrec = 0;

    if (len == 0) {
        // Length 0: always pass nil.
        lua_pushnil(L);
    } else switch (TYPEOF(x)) {
        // Otherwise: switch on type...
        case NILSXP: // NULL
            lua_pushnil(L);
            break;
        case SYMSXP: // symbols
            Rcpp::stop("Cannot convert SYMSXP to Lua.");
            break;
        case LISTSXP: // pairlists
            Rcpp::stop("Cannot convert LISTSXP to Lua.");
            break;
        case CLOSXP: // closures
            Rcpp::stop("Cannot convert CLOSXP to Lua.");
            break;
        case ENVSXP: // environments
            Rcpp::stop("Cannot convert ENVSXP to Lua.");
            break;
        case PROMSXP: // promises
            Rcpp::stop("Cannot convert PROMSXP to Lua.");
            break;
        case LANGSXP: // language objects
            Rcpp::stop("Cannot convert LANGSXP to Lua.");
            break;
        case SPECIALSXP: // special functions
            Rcpp::stop("Cannot convert SPECIALSXP to Lua.");
            break;
        case BUILTINSXP: // builtin functions
            Rcpp::stop("Cannot convert BUILTINSXP to Lua.");
            break;
        case CHARSXP: // internal character strings
            Rcpp::stop("Cannot convert CHARSXP to Lua.");
            break;
        case LGLSXP: // logical vectors: s, a, t
            if (as == 's' && len == 1) {
                // Primitive
                lua_pushboolean(L, LOGICAL_ELT(x, 0));
            } else if (as == 's' || as == 't') {
                // Table
                if (names != R_NilValue) {
                    for (unsigned int i = 0; i < len; ++i) // TODO and what if string is NA or if names is not character?
                        if (LENGTH(STRING_ELT(names, i)) > 0)
                            ++nrec;
                }
                lua_createtable(L, len - nrec, nrec);
                for (unsigned int i = 0; i < len; ++i)
                {
                    if (names != R_NilValue && LENGTH(STRING_ELT(names, i)) > 0) {
                        lua_pushstring(L, CHAR(STRING_ELT(names, i))); // TODO what if string is NA?
                        lua_pushboolean(L, LOGICAL_ELT(x, i));
                        lua_rawset(L, -3); // {-3}[{-2}] = {-1}; pop(2)
                    } else {
                        lua_pushboolean(L, LOGICAL_ELT(x, i));
                        lua_rawseti(L, -2, i + 1); // {-2}[i+1] = {-1}; pop(1)
                    }
                }
            } else if (as == 'a') {
                // Array
                lua_createtable(L, len, 0);
                for (unsigned int i = 0; i < len; ++i)
                {
                    lua_pushboolean(L, LOGICAL_ELT(x, i));
                    lua_rawseti(L, -2, i + 1); // {-2}[i+1] = {-1}; pop(1)
                }
            } else {
                Rcpp::stop("Unrecognised args code ", as, " for type ", Rf_type2char(TYPEOF(x)));
            }
            break;
        case INTSXP: // integer vectors: s, a, t
            lua_pushinteger(L, Rcpp::as<Rcpp::IntegerVector>(x)[0]);
            break;
        case REALSXP: // numeric vectors: s, a, t
            lua_pushnumber(L, Rcpp::as<Rcpp::NumericVector>(x)[0]);
            break;
        case CPLXSXP: // complex vectors
            Rcpp::stop("Cannot convert CPLXSXP to Lua.");
            break;
        case STRSXP: // character vectors: s, a, t
            lua_pushstring(L, Rcpp::as<Rcpp::StringVector>(x)[0]);
            break;
        case DOTSXP: // dot-dot-dot object
            Rcpp::stop("Cannot convert DOTSXP to Lua.");
            break;
        case ANYSXP: // make "any" args work
            Rcpp::stop("Cannot convert ANYSXP to Lua.");
            break;
        case VECSXP: // list (generic vector): s, a, t
            Rcpp::stop("No list yet");
            break;
        case EXPRSXP: // expression vector
            Rcpp::stop("Cannot convert EXPRSXP to Lua.");
            break;
        case BCODESXP: // byte code
            Rcpp::stop("Cannot convert BCODESXP to Lua.");
            break;
        case EXTPTRSXP: // external pointer: '*'
            lua_pushlightuserdata(L, Rcpp::as<void*>(x));
            break;
        case WEAKREFSXP: // weak reference
            Rcpp::stop("Cannot convert WEAKREFSXP to Lua.");
            break;
        case RAWSXP: // raw vector
            Rcpp::stop("Cannot convert RAWSXP to Lua.");
            break;
        case S4SXP: // S4 classes not of simple type
            Rcpp::stop("Cannot convert S4SXP to Lua.");
            break;
        default:
            Rcpp::stop("Unknown R type encountered.");
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
            // Add each table entry to a list
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
