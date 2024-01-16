typedef struct lua_State lua_State;

// This is needed because Rcpp doesn't handle extern "C" void x() well --
// other extern "C" signatures, and non-extern "C" void x(), are fine.
extern "C" void luajr_reset();
