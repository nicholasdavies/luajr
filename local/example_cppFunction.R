library(Rcpp)
library(luajr)

# Example: sourcing a C++ function
cppFunction('
void example3()
{
    lua_State* L = luajr_getstate(R_NilValue);
    lua_pushinteger(L, 100);
    Rcpp::Rcout << "Ciao, world with stack size " << lua_gettop(L) << "!\\n";
    lua_pop(L, 1);
}
', depends = "luajr", verbose = TRUE);

# Notes: Here, depends = "luajr" includes the appropriate header files and
# automatically loads the Lua/LuaJIT/luajr APIs.
example3()
