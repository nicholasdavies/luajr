---------------------
-- 1. INTERNAL API --
---------------------

-- Load 'internal' API for interfacing with R (mirrored in ./src/lua_api.cpp)
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

// Dummy NULL type
typedef struct { int _; } NULL_t;

// NA values
extern int TRUE_logical;
extern int FALSE_logical;
extern int NA_logical;
extern int NA_integer;
extern double NA_real;
extern SEXP NA_character;

// Functions to populate reference types
void SetLogicalRef(logical_rt* x, SEXP s);
void SetIntegerRef(integer_rt* x, SEXP s);
void SetNumericRef(numeric_rt* x, SEXP s);
void SetCharacterRef(character_rt* x, SEXP s);

// Functions to allocate reference types
// The Alloc* functions call R_PreserveObject() on the underlying SEXP, so we
// call Release in garbage collection for the corresponding R_ReleaseObject().
void AllocLogical(logical_rt* x, ptrdiff_t size);
void AllocInteger(integer_rt* x, ptrdiff_t size);
void AllocIntegerCompact1N(integer_rt* x, ptrdiff_t N);
void AllocNumeric(numeric_rt* x, ptrdiff_t size);
void AllocCharacter(character_rt* x, ptrdiff_t size);
void AllocCharacterNA(character_rt* x, ptrdiff_t size);
void AllocCharacterTo(character_rt* x, ptrdiff_t size, const char* v);
void Release(SEXP s);

// Functions to populate vector types
void SetLogicalVec(logical_vt* x, SEXP s);
void SetIntegerVec(integer_vt* x, SEXP s);
void SetNumericVec(numeric_vt* x, SEXP s);
// character handled separately

// Functions to get attributes
int GetAttrType(SEXP s, const char* k);
SEXP GetAttrSEXP(SEXP s, const char* k);

// Functions to set attributes
void SetAttrLogicalRef(SEXP s, const char* k, logical_rt* v);
void SetAttrIntegerRef(SEXP s, const char* k, integer_rt* v);
void SetAttrNumericRef(SEXP s, const char* k, numeric_rt* v);
void SetAttrCharacterRef(SEXP s, const char* k, character_rt* v);
void SetMatrixColnamesCharacterRef(SEXP s, character_rt* v);

// To get/set string vectors
const char* GetCharacterElt(SEXP s, ptrdiff_t k);
void SetCharacterElt(SEXP s, ptrdiff_t k, const char* v);

// For vector types' manual memory management
void* malloc(size_t size);
void free(void* ptr);

// Other C functions
size_t strlen(const char* str);
]]
local internal = ffi.load(luajr_dylib_path)


