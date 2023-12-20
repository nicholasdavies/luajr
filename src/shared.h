// [[Rcpp::plugins(cpp11)]]

// Forward declarations
struct SEXPREC;
struct lua_State;
typedef SEXPREC* SEXP;

// Globals
extern lua_State* L0;       // The shared global Lua state
extern SEXP RObjRetSymbol;  // Cached lookup symbol for robj_ret

// Move values between R and Lua (push_to.cpp)
void luajr_pushsexp(lua_State* L, SEXP x, char as);
SEXP luajr_tosexp(lua_State* L, int index);
void R_pass_to_Lua(lua_State* L, SEXP args, const char* acode);
SEXP Lua_return_to_R(lua_State* L, int nret);

// R API functions and related functions
SEXP luajr_open();
lua_State* luajr_getstate(SEXP Lxp);

// Lua API functions
extern "C" int AllocRDataMatrix(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);
extern "C" int AllocRDataFrame(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);
