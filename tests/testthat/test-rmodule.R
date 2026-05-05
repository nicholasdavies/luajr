test_that("R.length works", {
    lua("R = require('R')")
    expect_identical(lua("return R.length(R.NilValue)"), 0)
    expect_identical(
        lua_func("function(x) return R.length(x) end", "S")(1:10),
        10
    )
})

test_that("R.type_string works", {
    lua("R = require('R')")
    expect_identical(
        lua_func("function(x) return R.type_string(x) end", "S")(1:5),
        "integer"
    )
    expect_identical(
        lua_func("function(x) return R.type_string(x) end", "S")(c(1.0, 2.0)),
        "double"
    )
    expect_identical(
        lua_func("function(x) return R.type_string(x) end", "S")(TRUE),
        "logical"
    )
    expect_identical(
        lua_func("function(x) return R.type_string(x) end", "S")(letters),
        "character"
    )
    expect_identical(
        lua_func("function(x) return R.type_string(x) end", "S")(list()),
        "list"
    )
})

test_that("R constants are accessible", {
    lua("R = require('R')")
    # NilValue round-trips as NULL
    expect_null(lua("return R.NilValue"))
    # TYPEOF on constants
    expect_identical(lua("return R.TYPEOF(R.NilValue)"), 0)
    expect_identical(lua("return R.TYPEOF(R.GlobalEnv)"), 4)
    # NA values are non-nil
    expect_true(lua("return R.NA_INTEGER ~= nil"))
    expect_true(lua("return R.NA_REAL ~= nil"))
    expect_true(lua("return R.NA_STRING ~= nil"))
    # Symbols are non-nil
    expect_true(lua("return R.NamesSymbol ~= nil"))
    expect_true(lua("return R.ClassSymbol ~= nil"))
    expect_true(lua("return R.DimSymbol ~= nil"))
})

test_that("R SEXPTYPEs match TYPEOF", {
    lua("R = require('R')")
    typeof_x = lua_func("function(x) return R.TYPEOF(x) end", "S")

    # Core types
    expect_identical(typeof_x(NULL),                    lua("return R.NILSXP"))      # 0
    expect_identical(typeof_x(as.name("foo")),          lua("return R.SYMSXP"))      # 1
    expect_identical(typeof_x(pairlist(a = 1, b = 2)),  lua("return R.LISTSXP"))     # 2
    expect_identical(typeof_x(mean),                    lua("return R.CLOSXP"))      # 3
    expect_identical(typeof_x(globalenv()),             lua("return R.ENVSXP"))      # 4
    # PROMSXP (5): promises evaluate on access, can't pass as bare object
    expect_identical(typeof_x(quote(a + b)),            lua("return R.LANGSXP"))     # 6
    expect_identical(typeof_x(`if`),                    lua("return R.SPECIALSXP"))  # 7
    expect_identical(typeof_x(`+`),                     lua("return R.BUILTINSXP"))  # 8
    # CHARSXP (9): internal type, not directly accessible from R

    # Vector types
    expect_identical(typeof_x(TRUE),                    lua("return R.LGLSXP"))      # 10
    expect_identical(typeof_x(1L),                      lua("return R.INTSXP"))      # 13
    expect_identical(typeof_x(1.0),                     lua("return R.REALSXP"))     # 14
    expect_identical(typeof_x(1+0i),                    lua("return R.CPLXSXP"))     # 15
    expect_identical(typeof_x("hello"),                 lua("return R.STRSXP"))      # 16
    # DOTSXP (17): internal, not directly accessible from R
    # ANYSXP (18): not a real object type
    expect_identical(typeof_x(list()),                  lua("return R.VECSXP"))      # 19
    expect_identical(typeof_x(expression(1 + 2)),       lua("return R.EXPRSXP"))     # 20
    # BCODESXP (21): internal bytecode, not directly accessible from R
    expect_identical(typeof_x(lua_open()),              lua("return R.EXTPTRSXP"))   # 22
    # WEAKREFSXP (23): not easily created from R
    expect_identical(typeof_x(as.raw(0)),               lua("return R.RAWSXP"))      # 24
    # OBJSXP (25): S4 objects, would require methods package
})
