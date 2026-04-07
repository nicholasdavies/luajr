---------------------
-- 1. INTERNAL API --
---------------------

-- 'Internal' API for interfacing with C, R; struct types
ffi.cdef[[
// Forward declarations
struct SEXPREC;
typedef struct SEXPREC* SEXP;

// Type codes
// See also: ./src/shared.h
enum
{
    // TODO xfer to use R.* types
    NULL_T = 0, //NILSXP,
    LIST_T = 19, //VECSXP,

    LOGICAL_T = 10, //LGLSXP,
    INTEGER_T = 13, //INTSXP,
    NUMERIC_T = 14, //REALSXP,
    CHARACTER_T = 16, //STRSXP,

    SEXP_T = 63, // Generic SEXP
    REFERENCE_T = 64,
    VECTOR_T = 128,

    LOGICAL_R =   LOGICAL_T   | REFERENCE_T,
    INTEGER_R =   INTEGER_T   | REFERENCE_T,
    NUMERIC_R =   NUMERIC_T   | REFERENCE_T,
    CHARACTER_R = CHARACTER_T | REFERENCE_T,
    LOGICAL_V =   LOGICAL_T   | VECTOR_T,
    INTEGER_V =   INTEGER_T   | VECTOR_T,
    NUMERIC_V =   NUMERIC_T   | VECTOR_T,
    CHARACTER_V = CHARACTER_T | VECTOR_T,
};

// Reference types
typedef struct { int* _p;    SEXP _s; } logical_rt;
typedef struct { int* _p;    SEXP _s; } integer_rt;
typedef struct { double* _p; SEXP _s; } numeric_rt;
typedef struct { SEXP _s; } character_rt;

// Vector types
typedef struct { int* p;    double n; double c; } logical_vt;
typedef struct { int* p;    double n; double c; } integer_vt;
typedef struct { double* p; double n; double c; } numeric_vt;

// For vector types' manual memory management
void* memcpy(void* dest, const void* src, size_t count);
void* malloc(size_t size);
void free(void* ptr);

// Other C functions
size_t strlen(const char* str);
]]
local internal = ffi.load(luajr_dylib_path)


