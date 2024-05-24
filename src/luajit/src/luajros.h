/* luajros.h
 * Contains patch for lib_os.c of LuaJIT to make exit() redirect to Rf_stop().
 * (C) 2024 Nicholas G. Davies
 */

extern void Rf_error(const char *, ...);

static void RConsole_exit(int status)
{
    if (status)
        Rf_error("Exiting with status %d", status);
    Rf_error("");
}

/* Redirect invocation of exit() in lib_os.c to the above function. */
#define exit RConsole_exit
