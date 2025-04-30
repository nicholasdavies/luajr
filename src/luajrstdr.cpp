// luajrstdr.cpp - define functions that are designed to replace certain
// C standard library functions called from code in LuaJIT itself. See also
// luajr/local/luajdstdr.h.

#include <stdio.h>
#include <stdlib.h>
extern "C" {
#include "lua.h"
}
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
extern "C" int R_WriteConsoleEx(const char *, int, int);
extern "C" int R_ReadConsole(const char *, unsigned char *, int, int);

// Exit functions

#undef EXIT_FAILURE
#define EXIT_FAILURE 0xDEADBEEF

extern "C" void luajr_Cexit(int exit_code)
{
    if (exit_code == EXIT_FAILURE)
        Rf_error("Exiting with status code EXIT_FAILURE. This likely corresponds "
                 "to a serious error triggered by LuaJIT. Running more luajr commands "
                 "may cause a crash. I recommend you save your work and restart R. "
                 "If this error persists, please report it to the luajr package "
                 "maintainers.");
    Rf_error("Exiting with status %d", exit_code);
}

// I/O stream definitions
FILE dummy1;
FILE dummy2;
FILE dummy3;
FILE* luajr_Cstdin = &dummy1;
FILE* luajr_Cstdout = &dummy2;
FILE* luajr_Cstderr = &dummy3;


// Standard output functions

extern "C" int luajr_Cfputs(const char* str, FILE* stream)
{
    if (stream == luajr_Cstdout || stream == luajr_Cstderr)
    {
        int otype = (stream == luajr_Cstdout ? 0 : 1);
        R_WriteConsoleEx(str, strlen(str), otype);
        return 0;
    }
    else if (stream == luajr_Cstdin)
        Rf_error("Illegal use of stdin in fputs from LuaJIT.");
    else
        return fputs(str, stream);
}

extern "C" int luajr_Cfputc(int ch, FILE* stream)
{
    static char cbuf[2] = { '\0', '\0' };

    if (stream == luajr_Cstdout || stream == luajr_Cstderr)
    {
        int otype = (stream == luajr_Cstdout ? 0 : 1);
        cbuf[0] = ch;
        R_WriteConsoleEx(cbuf, strlen(cbuf), otype);
        return ch;
    }
    else if (stream == luajr_Cstdin)
        Rf_error("Illegal use of stdin in fputc from LuaJIT.");
    else
        return fputc(ch, stream);
}

extern "C" int luajr_Cputchar(int ch)
{
    return luajr_Cfputc(ch, luajr_Cstdout);
}

extern "C" int luajr_Cfflush(FILE* stream)
{
    if (stream == luajr_Cstdout || stream == luajr_Cstderr)
    {
        R_FlushConsole();
        return 0;
    }
    else if (stream == luajr_Cstdin)
        Rf_error("Illegal use of stdin in fflush from LuaJIT.");
    else
        return fflush(stream);
}

extern "C" int luajr_Cvfprintf(FILE* stream, const char* format, va_list vlist)
{
    static const int outsize = 4096;
    static char out[outsize];

    if (stream == luajr_Cstdout || stream == luajr_Cstderr)
    {
        int otype = (stream == luajr_Cstdout ? 0 : 1);
        int ret = vsnprintf(out, outsize, format, vlist);
        R_WriteConsoleEx(out, strlen(out), otype);
        if (ret > outsize)
            Rf_warning("Output truncated at %d characters.", outsize - 1);
        return ret;
    }
    else if (stream == luajr_Cstdin)
        Rf_error("Illegal use of stdin in vfprintf from LuaJIT.");
    else
        return vfprintf(stream, format, vlist);
}

extern "C" int luajr_Cfprintf(FILE* stream, const char* format, ...)
{
    if (stream == luajr_Cstdout || stream == luajr_Cstderr)
    {
        va_list args;
        va_start(args, format);
        int ret = luajr_Cvfprintf(stream, format, args);
        va_end(args);
        return ret;
    }
    else if (stream == luajr_Cstdin)
    {
        Rf_error("Illegal use of stdin in fprintf from LuaJIT.");
    }
    else
    {
        va_list args;
        va_start(args, format);
        int ret = vfprintf(stream, format, args);
        va_end(args);
        return ret;
    }
}

extern "C" size_t luajr_Cfwrite(const void* buffer, size_t size, size_t count, FILE* stream)
{
    if (stream == luajr_Cstdout || stream == luajr_Cstderr)
    {
        if (size == 1)
        {
            int otype = (stream == luajr_Cstdout ? 0 : 1);
            R_WriteConsoleEx((const char*)buffer, count, otype);
            return count;
        }
        else
            Rf_error("Only size == 1 is supported in fwrite from LuaJIT.");
    }
    else if (stream == luajr_Cstdin)
        Rf_error("Illegal use of stdin in fwrite from LuaJIT.");
    else
        return fwrite(buffer, size, count, stream);
}


// Standard input functions

#define RCONSOLE_BUFSIZE 4096

static unsigned char RConsoleBuf[RCONSOLE_BUFSIZE];
static int RConsoleBufCnt = 0;
static char* RConsoleBufPtr = (char*)RConsoleBuf;

extern "C" int luajr_Cfscanf(FILE* stream, const char* format, ...)
{
    int ret;
    va_list args;
    va_start(args, format);

    if (stream == luajr_Cstdin)
    {
        if (strcmp(format, LUA_NUMBER_SCAN) == 0) // Called from file:read("n")
        {
            int nchar;
            lua_Number* d;

            /* Get the pointer to lua_Number passed in by io_file_readnum for scanning */
            d = va_arg(args, lua_Number*);

            while (1)
            {
                /* Read another line if no characters left in input buffer */
                if (RConsoleBufCnt <= 0)
                {
                    if (!R_ReadConsole("", RConsoleBuf, RCONSOLE_BUFSIZE, 0))
                        return 0;
                    RConsoleBufPtr = (char*)RConsoleBuf;
                    RConsoleBufCnt = strlen(RConsoleBufPtr);

                    if (RConsoleBufCnt == RCONSOLE_BUFSIZE - 1)
                    {
                        Rf_warning("Line buffer size %d reached.", RCONSOLE_BUFSIZE);
                    }
                }

                /* Read in one number from the buffer */
                ret = sscanf(RConsoleBufPtr, LUA_NUMBER_SCAN "%n", d, &nchar);

                /* If sscanf successfully read in a number, adjust buffer and break. */
                if (ret == 1)
                {
                    RConsoleBufPtr += nchar;
                    RConsoleBufCnt -= nchar;
                    /* Discard any terminal newline */
                    if (RConsoleBufCnt > 0 && *RConsoleBufPtr == '\n')
                    {
                        ++RConsoleBufPtr;
                        --RConsoleBufCnt;
                    }
                    break;
                }

                /* If sscanf failed (either invalid input or EOF) junk the buffer. */
                RConsoleBufCnt = 0;

                /* Break out if invalid input; keep looping if EOF. */
                if (ret == 0)
                {
                    break;
                }
            }

            va_end(args);
            return ret;
        }
        else
        {
            Rf_error("Illegal call to fscanf from LuaJIT.");
        }
    }
    else if (stream == luajr_Cstdout || stream == luajr_Cstderr)
    {
        Rf_error("Illegal use of stdout/stderr in fscanf from LuaJIT.");
    }
    else
    {
        ret = vfscanf(stream, format, args);
        va_end(args);
        return ret;
    }
}

extern "C" char* luajr_Cfgets(char* str, int count, FILE* stream)
{
    if (stream == luajr_Cstdin)
    {
        /* If there are characters left in the input buffer, use those */
        if (RConsoleBufCnt > 0)
        {
            strncpy(str, RConsoleBufPtr, count - 1);
            str[count - 1] = '\0';
            count = strlen(str);
            RConsoleBufPtr += count;
            RConsoleBufCnt -= count;

            return str;
        }
        else
        {
            if (R_ReadConsole("", (unsigned char*)str, count, 0))
                return str;
            return NULL;
        }
    }
    else if (stream == luajr_Cstdout || stream == luajr_Cstderr)
        Rf_error("Illegal use of stdout/stderr in fgets from LuaJIT.");
    else
        return fgets(str, count, stream);
}

extern "C" size_t luajr_Cfread(void* buffer, size_t size, size_t count, FILE* stream)
{
    if (stream == luajr_Cstdin)
    {
        if (size == 1)
        {
            /* If there are characters left in the input buffer, use those */
            if (RConsoleBufCnt > 0)
            {
                size_t n = count < RConsoleBufCnt ? count : RConsoleBufCnt;
                memcpy(buffer, RConsoleBufPtr, n);
                RConsoleBufPtr += n;
                RConsoleBufCnt -= n;
                return n;
            }
            else
            {
                size_t len;
                /* Still use the input buffer, as R_ReadConsole adds a terminating
                 * null, which is not what fread is supposed to do. */
                if (!R_ReadConsole("", RConsoleBuf, RCONSOLE_BUFSIZE, 0))
                    return 0;
                len = strlen((char*)RConsoleBuf);
                memcpy(buffer, (char*)RConsoleBuf, len);
                return len;
            }
        }
        else
            Rf_error("Only size == 1 is supported in fread from LuaJIT.");
    }
    else if (stream == luajr_Cstdout || stream == luajr_Cstderr)
        Rf_error("Illegal use of stdout/stderr in fread from LuaJIT.");
    else
        return fread(buffer, size, count, stream);
}

// Additional I/O functions, designed to just fail (on use with standard
// streams) or redirect to library versions (on use with any other streams).
#define IO_FUNC(RET, NAME, ARGS, NEWCALL)                      \
    extern "C" RET luajr_C##NAME ARGS                          \
    {                                                          \
        if (stream == luajr_Cstdin || stream == luajr_Cstdout  \
            || stream == luajr_Cstderr)                        \
        {                                                      \
            Rf_error("Cannot use %s on standard streams. "     \
                "This may be a luajr error.", #NAME);          \
        }                                                      \
        NEWCALL;                                               \
    }                                                          \

IO_FUNC(int,        fclose,     (FILE* stream),
    return fclose(stream))
IO_FUNC(FILE*,      freopen,    (const char* filename, const char* mode, FILE* stream),
    return freopen(filename, mode, stream))
IO_FUNC(void,       setbuf,     (FILE* stream, char* buf),
    setbuf(stream, buf))
IO_FUNC(int,        setvbuf,    (FILE* stream, char* buf, int mode, size_t size),
    return setvbuf(stream, buf, mode, size))
IO_FUNC(int,        vfscanf,    (FILE* stream, const char* format, va_list arg),
    return vfscanf(stream, format, arg))
IO_FUNC(int,        ungetc,     (int c, FILE* stream),
    return ungetc(c, stream))
IO_FUNC(int,        fgetpos,    (FILE* stream, fpos_t* pos),
    return fgetpos(stream, pos))
IO_FUNC(int,        fseek,      (FILE* stream, long int offset, int whence),
    return fseek(stream, offset, whence))
IO_FUNC(int,        fsetpos,    (FILE* stream, const fpos_t* pos),
    return fsetpos(stream, pos))
IO_FUNC(long int,   ftell,      (FILE* stream),
    return ftell(stream))
IO_FUNC(void,       rewind,     (FILE* stream),
    return rewind(stream))
IO_FUNC(void,       clearerr,   (FILE* stream),
    return clearerr(stream))
IO_FUNC(int,        feof,       (FILE* stream),
    return feof(stream))
IO_FUNC(int,        ferror,     (FILE* stream),
    return ferror(stream))

