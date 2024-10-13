/* luajrio.h
 * Contains patch for lib_io.c of LuaJIT to make reading from stdin redirect to
 * the R console.
 * (C) 2024 Nicholas G. Davies
 */

#include <stdarg.h>
#include <string.h>
#include <ctype.h>

extern int R_ReadConsole(const char *, unsigned char *, int, int);
extern void Rf_warning(const char * format, ...);

// R does not allow reading lines of more than 1024 characters (including terminating \n\0).
#define RCONSOLE_BUFSIZE 1024

static unsigned char RConsoleBuf[RCONSOLE_BUFSIZE];
static int RConsoleBufCnt = 0;
static char* RConsoleBufPtr = (char*)RConsoleBuf;

static int RConsole_fscanf(FILE* stream, const char* format, ...)
{
    int ret;
    va_list args;
    va_start(args, format);

    if (stream == stdin && strcmp(format, LUA_NUMBER_SCAN) == 0)
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
        ret = vfscanf(stream, format, args);
        va_end(args);
        return ret;
    }
}

static char* RConsole_fgets(char* s, int size, FILE* stream)
{
    if (stream == stdin)
    {
        /* If there are characters left in the input buffer, use those */
        if (RConsoleBufCnt > 0)
        {
            strncpy(s, RConsoleBufPtr, size - 1);
            s[size - 1] = '\0';
            size = strlen(s);
            RConsoleBufPtr += size;
            RConsoleBufCnt -= size;

            return s;
        }
        else
        {
            if (R_ReadConsole("", (unsigned char*)s, size, 0))
                return s;
            return NULL;
        }
    }
    else
    {
        return fgets(s, size, stream);
    }
}

static size_t RConsole_fread(void* ptr, size_t size, size_t nmemb, FILE* stream)
{
    if (stream == stdin && size == 1)
    {
        /* If there are characters left in the input buffer, use those */
        if (RConsoleBufCnt > 0)
        {
            size_t n = nmemb < RConsoleBufCnt ? nmemb : RConsoleBufCnt;
            memcpy(ptr, RConsoleBufPtr, n);
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
            memcpy(ptr, (char*)RConsoleBuf, len);
            return len;
        }
    }
    else
    {
        return fread(ptr, size, nmemb, stream);
    }
}

/* These #defines redirect invocations in lib_io.c to the above functions. */
#define fscanf RConsole_fscanf
#define fgets RConsole_fgets
#define fread RConsole_fread
