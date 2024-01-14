// [[Rcpp::plugins(cpp11)]]

// Forward declarations
struct lua_State;
struct SEXPREC;
typedef SEXPREC* SEXP;

// Globals
extern lua_State* L0;       // The shared global Lua state
extern SEXP RObjRetSymbol;  // Cached lookup symbol for robj_ret

// Move values between R and Lua (push_to.cpp)
void luajr_pushsexp(lua_State* L, SEXP x, char as);
SEXP luajr_tosexp(lua_State* L, int index);
void luajr_pass(lua_State* L, SEXP args, const char* acode);
SEXP luajr_return(lua_State* L, int nret);

// R API functions and related functions
SEXP luajr_open();
lua_State* luajr_newstate();
void luajr_reset();
lua_State* luajr_getstate(SEXP Lx);

// Lua API functions
extern "C" int AllocRDataMatrix(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);
extern "C" int AllocRDataFrame(unsigned int nrow, unsigned int ncol, const char* names[], double** ptrs);

// Helper functions
SEXP luajr_makepointer(void* x, int tag_code, void (*finalize)(SEXP));
void* luajr_getpointer(SEXP handle, int tag_code);
void luajr_pcall(lua_State* L, int nargs, int nresults, const char* funcdesc);

