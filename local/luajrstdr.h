/* luajrstdr.h
 * Sets up various patches for C standard library functions used by LuaJIT that
 * we want to provide alternative definitions for, so that LuaJIT operates well
 * in an R context. Specifically, we want to redefine exit() to not completely
 * quit R but just stop the currently running code, and we want to redefine I/O
 * functions to redirect stdin, stdout, and stderr to the R console.
 * (C) 2025 Nicholas G. Davies
 */

#ifndef LUAJRSTDR_H
#define LUAJRSTDR_H

/* Don't do any of this in the context of the luajit/src/host VM building. */
#ifndef _BUILDVM_H

/* Ensure stdlib.h and stdio.h have been included before this file. */
#include <stdlib.h>
#include <stdio.h>

/* For va_list */
#include <stdarg.h>

/* No-return attribute (from lj_def.h) */
#if defined(__GNUC__) || defined(__clang__) || defined(__psp2__)
#define NORET	__attribute__((noreturn))
#elif defined(_MSC_VER)
#define NORET	__declspec(noreturn)
#endif

/* Declare our alternative versions. */

/* Exit function; we need to redefine these so that when LuaJIT calls exit(),
 * instead of completely quitting R, we can give a chance to the user to
 * recover. */
NORET extern void luajr_Cexit(int exit_code);

/* Standard streams */
extern FILE* luajr_Cstdin;
extern FILE* luajr_Cstdout;
extern FILE* luajr_Cstderr;

/* I/O functions used by LuaJIT on standard streams;
 * we need to redefine these so that LuaJIT will not try to read from standard
 * input or try to write to standard output / stderr.
 */
extern int luajr_Cfputs(const char* str, FILE* stream);
extern int luajr_Cfputc(int ch, FILE* stream);
extern int luajr_Cputchar(int ch);
extern int luajr_Cfflush(FILE* stream);
extern int luajr_Cvfprintf(FILE* stream, const char* format, va_list vlist);
extern int luajr_Cfprintf(FILE* stream, const char* format, ...);
extern size_t luajr_Cfwrite(const void* buffer, size_t size, size_t count, FILE* stream);
extern int luajr_Cfscanf(FILE* stream, const char* format, ...);
extern char* luajr_Cfgets(char* str, int count, FILE* stream);
extern size_t luajr_Cfread(void* buffer, size_t size, size_t count, FILE* stream);

/* I/O functions NOT (as far as I can see) used by LuaJIT on standard streams;
 * nonetheless we want to redirect these to "safe" versions that will just quit
 * the current R execution when there is an attempt to use them on standard
 * input, output, or error streams. The reason for doing this is that we may
 * redefine stdin, stdout, and stderr to something which does not actually
 * point to a valid FILE, so we should intercept these to avoid crashes (and
 * also to be aware of what other I/O functions may need to be adapted to work
 * with standard streams in an R context. */
extern int luajr_Cfclose(FILE* stream);
extern FILE* luajr_Cfreopen(const char* filename, const char* mode, FILE* stream);
extern void luajr_Csetbuf(FILE* stream, char* buf);
extern int luajr_Csetvbuf(FILE* stream, char* buf, int mode, size_t size);
extern int luajr_Cvfscanf(FILE* stream, const char* format, va_list arg);
extern int luajr_Cungetc(int c, FILE* stream);
extern int luajr_Cfgetpos(FILE* stream, fpos_t* pos);
extern int luajr_Cfseek(FILE* stream, long int offset, int whence);
extern int luajr_Cfsetpos(FILE* stream, const fpos_t* pos);
extern long int luajr_Cftell(FILE* stream);
extern void luajr_Crewind(FILE* stream);
extern void luajr_Cclearerr(FILE* stream);
extern int luajr_Cfeof(FILE* stream);
extern int luajr_Cferror(FILE* stream);

#undef NORET

/* Undefine all relevant names, some of which may be macros. */
#undef EXIT_FAILURE
#undef exit

#undef stdin
#undef stdout
#undef stderr

#undef fputs
#undef fputc
#undef putc
#undef putchar
#undef fflush
#undef vfprintf
#undef fprintf
#undef fwrite
#undef fscanf
#undef fgets
#undef fread

#undef fclose
#undef freopen
#undef setbuf
#undef setvbuf
#undef vfscanf
#undef ungetc
#undef fgetpos
#undef fseek
#undef fsetpos
#undef ftell
#undef rewind
#undef clearerr
#undef feof
#undef ferror


/* Redirect symbols to our versions. */
#define EXIT_FAILURE 0xDEADBEEF
#define exit luajr_Cexit

#define stdin luajr_Cstdin
#define stdout luajr_Cstdout
#define stderr luajr_Cstderr

#define fputs luajr_Cfputs
#define fputc luajr_Cfputc
#define putc luajr_Cfputc
#define putchar luajr_Cputchar
#define fflush luajr_Cfflush
#define vfprintf luajr_Cvfprintf
#define fprintf luajr_Cfprintf
#define fwrite luajr_Cfwrite
#define fscanf luajr_Cfscanf
#define fgets luajr_Cfgets
#define fread luajr_Cfread

#define fclose luajr_Cfclose
#define freopen luajr_Cfreopen
#define setbuf luajr_Csetbuf
#define setvbuf luajr_Csetvbuf
#define vfscanf luajr_Cvfscanf
#define ungetc luajr_Cungetc
#define fgetpos luajr_Cfgetpos
#define fseek luajr_Cfseek
#define fsetpos luajr_Cfsetpos
#define ftell luajr_Cftell
#define rewind luajr_Crewind
#define clearerr luajr_Cclearerr
#define feof luajr_Cfeof
#define ferror luajr_Cferror

#endif /* _BUILDVM_H */

#endif /* LUAJRSTDR_H */
