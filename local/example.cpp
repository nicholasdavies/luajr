// [[Rcpp::depends(luajr)]]
#include <Rcpp.h>
#include <luajr_api.h>
#include <luajr_funcdef.hpp>

// [[Rcpp::export]]
void exampleS()
{
    lua_State* L = luajr_getstate(R_NilValue);
    lua_pushinteger(L, 100);
    Rcpp::Rcout << "Goodbye, world with stack size " << lua_gettop(L) << "!\n";
    lua_pop(L, 1);
}
