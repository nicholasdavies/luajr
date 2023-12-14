#define API_FUNCTION(return_type, func_name, ...) \
return_type (*func_name)(__VA_ARGS__) = reinterpret_cast<return_type (*)(__VA_ARGS__)>(R_GetCCallable("luajr", #func_name));
#include "luajr_funcs.h"
#undef API_FUNCTION
