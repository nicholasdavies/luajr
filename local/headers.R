library(stringr)

setwd(here::here())

sed = function(infile, outfile, pattern = NULL)
{
    lines = readLines(infile)
    if (!is.null(pattern)) {
        lines = str_replace_all(lines, pattern)
    }
    writeLines(lines, outfile)
}

# Modify Makefile

sed("./src/luajit/src/Makefile", "./src/luajit/src/Makefile", c(
    "^default all:\t\\$\\(TARGET_T\\)$" = "default all:\t$(TARGET_O)"
))

# Modify lj_arch.h
# LuaJIT's profiler uses SIGPROF on POSIX by default, but might possibly
# conflict with the R session in RStudio (and potentially other IDEs) which
# also uses signal handling. This switches to a dedicated pthread timer thread
# instead, which avoids the signal conflict entirely. This appears unnecessary
# now that tooling has been removed from push_to.cpp, but keeping here in case
# it is needed in future.

# sed("./src/luajit/src/lj_arch.h", "./src/luajit/src/lj_arch.h", c(
#     "^#define LJ_PROFILE_SIGPROF\t1$" = "#define LJ_PROFILE_PTHREAD\t1"
# ))

# Modify lj_def.h

sed("./src/luajit/src/lj_def.h", "./src/luajit/src/lj_def.h", c(
    '^#include <stdlib.h>$' = '#include <stdlib.h>\n#include "luajrstdr.h"'
))

# Create luajr/lua/luajit header files

sed("./src/luajit/src/luaconf.h", "./inst/include/luajr_luaconf.h")

sed("./src/luajit/src/lua.h", "./inst/include/luajr_lua.h", c(
    r"(^LUA_API ([^(]*)\(?(lua_[a-z_]+)\s*\)?(.*)$)" = r"(extern \1 (*\2)\3)",
    r"(#include "luaconf.h")" = r"(#include "luajr_luaconf.h")"
))

sed("./src/luajit/src/luajit.h", "./inst/include/luajr_luajit.h", c(
    r"(^LUA_API ([^(]*)\(?(luaJIT_[a-z_]+)\s*\)?(.*)$)" = r"(extern \1 (*\2)\3)",
    r"(#include "lua.h")" = r"(#include "luajr_lua.h")"
))

sed("./src/luajit/src/lualib.h", "./inst/include/luajr_lualib.h", c(
    r"(^LUALIB_API ([^(]*)\(?(lua(open|L)_[a-z_]+)\s*\)?(.*)$)" = r"(extern \1 (*\2)\4)",
    r"(#include "lua.h")" = r"(#include "luajr_lua.h")"
))

sed("./src/luajit/src/lauxlib.h", "./inst/include/luajr_lauxlib.h", c(
    r"(^LUALIB_API ([^(]*)\(?(luaL_[a-z_]+)\s*\)?(.*)$)" = r"(extern \1 (*\2)\3)",
    r"(#include "lua.h")" = r"(#include "luajr_lua.h")"
))
