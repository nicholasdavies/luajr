// luajrstdr.cpp - define functions that are designed to replace certain
// C standard library functions called from code in LuaJIT itself. See also
// luajr/local/luajdstdr.h.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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
    if (exit_code == (int)EXIT_FAILURE)
        Rf_error("Exiting with status code EXIT_FAILURE. This likely corresponds "
                 "to a serious error triggered by Lua code. Running more luajr commands "
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
        R_WriteConsoleEx(str, (int)strlen(str), otype);
        return 0;
    }
    else if (stream == luajr_Cstdin)
        Rf_error("Illegal use of stdin in fputs from luajr.");
    else
        return fputs(str, stream);
}

extern "C" int luajr_Cfputc(int ch, FILE* stream)
{
    if (stream == luajr_Cstdout || stream == luajr_Cstderr)
    {
        int otype = (stream == luajr_Cstdout ? 0 : 1);
        // R_WriteConsoleEx takes a length, but its standard back-end
        // (Rstd_WriteConsole in sys-std.c) prints via printf("%s", buf),
        // which ignores the length and requires NUL termination.
        char c[2] = { (char)ch, '\0' };
        R_WriteConsoleEx(c, 1, otype);
        return ch;
    }
    else if (stream == luajr_Cstdin)
        Rf_error("Illegal use of stdin in fputc from luajr.");
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
        Rf_error("Illegal use of stdin in fflush from luajr.");
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
        R_WriteConsoleEx(out, (int)strlen(out), otype);
        if (ret >= outsize)
            Rf_warning("Output truncated at %d characters.", outsize - 1);
        return ret;
    }
    else if (stream == luajr_Cstdin)
        Rf_error("Illegal use of stdin in vfprintf from luajr.");
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
        Rf_error("Illegal use of stdin in fprintf from luajr.");
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
            // R_WriteConsoleEx's standard back-end requires NUL termination
            // (see luajr_Cfputc). The input buffer is not guaranteed to be
            // NUL-terminated, so copy through a NUL-terminated static chunk,
            // chunking when count exceeds the buffer size.
            static const size_t chunksize = 4096;
            static char chunk[chunksize];
            const char* p = (const char*)buffer;
            size_t remaining = count;
            while (remaining > 0)
            {
                size_t n = remaining < chunksize - 1 ? remaining : chunksize - 1;
                memcpy(chunk, p, n);
                chunk[n] = '\0';
                R_WriteConsoleEx(chunk, (int)n, otype);
                p += n;
                remaining -= n;
            }
            return count;
        }
        else
            Rf_error("Only size == 1 is supported in fwrite from luajr.");
    }
    else if (stream == luajr_Cstdin)
        Rf_error("Illegal use of stdin in fwrite from luajr.");
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
                    RConsoleBufCnt = (int)strlen(RConsoleBufPtr);

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
            Rf_error("Illegal call to fscanf from luajr.");
        }
    }
    else if (stream == luajr_Cstdout || stream == luajr_Cstderr)
    {
        Rf_error("Illegal use of stdout/stderr in fscanf from luajr.");
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
        if (RConsoleBufCnt == 0)
        {
            /* No buffer, read a fresh line. */
            if (!R_ReadConsole("", RConsoleBuf, RCONSOLE_BUFSIZE, 0))
                return NULL;
            RConsoleBufPtr = (char*)RConsoleBuf;
            RConsoleBufCnt = (int)strlen((char*)RConsoleBuf);
        }

        /* Copy up to count - 1 chars or stop at newline (inclusive). */
        int max = count - 1 < RConsoleBufCnt ? count - 1 : RConsoleBufCnt;
        char* nl = (char*)memchr(RConsoleBufPtr, '\n', max);
        int n = nl ? (int)(nl - RConsoleBufPtr) + 1 : max;
        memcpy(str, RConsoleBufPtr, n);
        str[n] = '\0';
        RConsoleBufPtr += n;
        RConsoleBufCnt -= n;
        return str;
    }
    else if (stream == luajr_Cstdout || stream == luajr_Cstderr)
        Rf_error("Illegal use of stdout/stderr in fgets from luajr.");
    else
        return fgets(str, count, stream);
}

extern "C" size_t luajr_Cfread(void* buffer, size_t size, size_t count, FILE* stream)
{
    if (stream == luajr_Cstdin)
    {
        if (size == 1)
        {
            if (RConsoleBufCnt == 0)
            {
                /* No buffer, read a fresh line. R_ReadConsole adds a
                 * terminating null, which fread is not supposed to write. */
                if (!R_ReadConsole("", RConsoleBuf, RCONSOLE_BUFSIZE, 0))
                    return 0;
                RConsoleBufPtr = (char*)RConsoleBuf;
                RConsoleBufCnt = (int)strlen((char*)RConsoleBuf);
            }

            /* Copy as much as fits, advancing the buffer state. Any leftover
             * stays available for the next fgets/fread call. */
            size_t n = count < (size_t)RConsoleBufCnt ? count : RConsoleBufCnt;
            memcpy(buffer, RConsoleBufPtr, n);
            RConsoleBufPtr += n;
            RConsoleBufCnt -= n;
            return n;
        }
        else
            Rf_error("Only size == 1 is supported in fread from luajr.");
    }
    else if (stream == luajr_Cstdout || stream == luajr_Cstderr)
        Rf_error("Illegal use of stdout/stderr in fread from luajr.");
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

