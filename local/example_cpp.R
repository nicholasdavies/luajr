# NOTE. Cannot test this using testthat because neither example compiles under
# the environment set by testthat, though they compile on their own. There are
# issues with the preprocessor not finding luajr_api.h, and then issues with
# the linker not linking to luajr either. Seems like it may be more trouble than
# it's worth to integrate this into formal testthat testing. But it should be
# part of package testing, ideally.

# Test whether we can use the Lua API from C++, using cppFunction
Rcpp::cppFunction('void exampleF() {
    lua_State* L = luajr_getstate(R_NilValue);
    lua_pushinteger(L, 100);
    Rcpp::Rcout << "Ciao, world with stack size " << lua_gettop(L) << "!\\n";
    lua_pop(L, 1);
}', depends = "luajr");

exampleF() == "Ciao, world with stack size 1!"

# Test whether we can use the Lua API from C++, using sourceCpp
Rcpp::sourceCpp("./local/example.cpp")
exampleS() == "Goodbye, world with stack size 1!"
