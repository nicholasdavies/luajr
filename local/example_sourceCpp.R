library(Rcpp)
library(luajr)

# Example: sourcing an external C++ file
sourceCpp("./local/example_sourceCpp.cpp", verbose = TRUE)
example1()

# This is the same
sourceCpp(code = "
// [[Rcpp::depends(luajr)]]
#include <luajr_api.h>
#include <luajr_funcdef.hpp>

// [[Rcpp::export]]
void example2()
{
    lua_State* L = luajr_getstate(R_NilValue);
    lua_pushinteger(L, 100);
    Rcpp::Rcout << \"Goodbye, world with stack size \" << lua_gettop(L) << \"!\\n\";
    lua_pop(L, 1);
}
");
example2()
