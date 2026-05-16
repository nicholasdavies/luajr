test_that("functions work", {
    # Extract the Lua function table.concat(table, sep) which creates a string
    # from a table with separator sep.
    table.concat = lua_func("table.concat", "$V, $C")
    expect_equal(table.concat(list("A", 1), "/"), "A/1")
})

test_that("pass by reference works", {
    identity = lua_func("function(x) return x end", "&.")
    expect_identical(identity(c(TRUE, FALSE, FALSE)), c(TRUE, FALSE, FALSE))
    expect_identical(identity(rep(0L, 10)), rep(0L, 10))
    expect_identical(identity(pi), pi)
    expect_identical(identity(letters), letters)
    expect_identical(identity(list(a = 1, b = pi, letters)), list(a = 1, b = pi, letters))
    expect_null(identity(NULL))

    # Pass and modify
    expect_identical(lua_func("function(x) x[1] = true return x end", "&.")(c(FALSE, FALSE, FALSE)), c(TRUE, FALSE, FALSE))
    expect_identical(lua_func("function(x) x[1] = 0 return x end", "&.")(c(1L, rep(0L, 9))), rep(0L, 10))
    expect_identical(lua_func("function(x) x[1] = x[1] + 1 return x end", "&.")(pi - 1), pi)
    expect_identical(lua_func("function(x) x[1] = 'a' return x end", "&.")(c('b', 'b', 'c')), letters[1:3])
    expect_identical(lua_func("function(x) x:set('b', math.pi) return x end", "&.")(list(a = 1, b = 0, letters)), list(a = 1, b = pi, letters))
})

test_that("pass by value (alias) works", {
    identity = lua_func("function(x) return x end", ".")
    expect_identical(identity(c(TRUE, FALSE, FALSE)), c(TRUE, FALSE, FALSE))
    expect_identical(identity(rep(0L, 10)), rep(0L, 10))
    expect_identical(identity(pi), pi)
    expect_identical(identity(letters), letters)
    expect_identical(identity(list(a = 1, b = pi, letters)), list(a = 1, b = pi, letters))
    expect_null(identity(NULL))

    # Pass and modify (COW: original unaffected, returned copy is modified)
    expect_identical(lua_func("function(x) x[1] = true return x end", ".")(c(FALSE, FALSE, FALSE)), c(TRUE, FALSE, FALSE))
    expect_identical(lua_func("function(x) x[1] = 0 return x end", ".")(c(1L, rep(0L, 9))), rep(0L, 10))
    expect_identical(lua_func("function(x) x[1] = x[1] + 1 return x end", ".")(pi - 1), pi)
    expect_identical(lua_func("function(x) x[1] = 'a' return x end", ".")(c('b', 'b', 'c')), letters[1:3])
    expect_identical(lua_func("function(x) x:set('b', math.pi) return x end", ".")(list(a = 1, b = 0, letters)), list(a = 1, b = pi, letters))
})

test_that("typed argcodes work", {
    identity = lua_func("function(x) return x end", ".")

    # Typed vector argcodes
    expect_identical(lua_func("function(x) return x end", "L")(c(TRUE, FALSE)), c(TRUE, FALSE))
    expect_identical(lua_func("function(x) return x end", "I")(1:5), 1:5)
    expect_identical(lua_func("function(x) return x end", "N")(c(1.5, 2.5)), c(1.5, 2.5))
    expect_identical(lua_func("function(x) return x end", "C")(c("a", "b")), c("a", "b"))
    expect_identical(lua_func("function(x) return x end", "V")(list(1, "two")), list(1, "two"))

    # Typed argcodes reject wrong types
    expect_error(lua_func("function(x) return x end", "L")(1:5))
    expect_error(lua_func("function(x) return x end", "I")("hello"))
    expect_error(lua_func("function(x) return x end", "N")("hello"))
    expect_error(lua_func("function(x) return x end", "C")(1:5))
    expect_error(lua_func("function(x) return x end", "V")(1:5))
})

test_that("coercion between integer and numeric works", {
    # N accepts integer, coerces to numeric
    expect_identical(lua_func("function(x) return x end", "N")(1:3), c(1, 2, 3))
    # I accepts numeric, coerces to integer
    expect_identical(lua_func("function(x) return x end", "I")(c(1, 2, 3)), 1:3)
})

test_that("strict argcode prevents coercion", {
    # !I rejects numeric
    expect_error(lua_func("function(x) return x end", "!I")(c(1, 2, 3)))
    # !N rejects integer
    expect_error(lua_func("function(x) return x end", "!N")(1:3))
})

test_that("strict argcode rejects NULL", {
    expect_error(lua_func("function(x) return x end", "!N")(NULL))
    expect_error(lua_func("function(x) return x end", "!.")(NULL))
})

test_that("native scalar argcodes work", {
    # $N gives a Lua number
    expect_identical(lua_func("function(x) return type(x) end", "$N")(1.5), "number")
    expect_identical(lua_func("function(x) return x end", "$N")(42), 42)

    # $L gives a Lua boolean
    expect_identical(lua_func("function(x) return type(x) end", "$L")(TRUE), "boolean")
    expect_identical(lua_func("function(x) return x end", "$L")(TRUE), TRUE)

    # $C gives a Lua string
    expect_identical(lua_func("function(x) return type(x) end", "$C")("hello"), "string")
    expect_identical(lua_func("function(x) return x end", "$C")("test"), "test")

    # $I gives a Lua number (coerced from integer)
    expect_identical(lua_func("function(x) return type(x) end", "$I")(1L), "number")
    expect_identical(lua_func("function(x) return x end", "$I")(10L), 10)

    # Native scalar errors on length > 1
    expect_error(lua_func("function(x) return x end", "$N")(c(1, 2)))

    # Native scalar pushes nil for length 0
    expect_null(lua_func("function(x) return x end", "$N")(numeric(0)))
})

test_that("native scalar pushes nil for NA", {
    expect_null(lua_func("function(x) return x end", "$L")(NA))
    expect_null(lua_func("function(x) return x end", "$I")(NA_integer_))
    expect_null(lua_func("function(x) return x end", "$N")(NA_real_))
    expect_null(lua_func("function(x) return x end", "$C")(NA_character_))
})

test_that("native value converts scalars and tables", {
    lua("R = require('R')")

    # Length 1 -> Lua scalar
    expect_identical(lua_func("function(x) return type(x) end", "$.")(1.5), "number")
    expect_identical(lua_func("function(x) return type(x) end", "$.")(TRUE), "boolean")
    expect_identical(lua_func("function(x) return type(x) end", "$.")("hi"), "string")

    # Length > 1 -> Lua table
    expect_identical(lua_func("function(x) return type(x) end", "$.")(c(1, 2)), "table")
    expect_identical(lua_func("function(x) return x[1] + x[2] end", "$.")(c(10, 20)), 30)

    # List -> Lua table
    expect_identical(lua_func("function(x) return type(x) end", "$.")(list(1, 2)), "table")
    expect_identical(lua_func("function(x) return x.a end", "$.")(list(a = 42)), 42)

    # NULL -> nil
    expect_null(lua_func("function(x) return x end", "$.")(NULL))
})

test_that("native list ($V) converts any vector to table", {
    # Numeric vector -> table
    expect_identical(lua_func("function(x) return x[1] + x[2] end", "$V")(c(10, 20)), 30)
    # Character vector -> table
    expect_identical(lua_func("function(x) return x[1] end", "$V")(c("hello", "world")), "hello")
    # Actual list -> table with names
    expect_identical(lua_func("function(x) return x.a end", "$V")(list(a = 99)), 99)
})

test_that("byref argcode works with typed codes", {
    # &N = byref numeric
    x = c(1, 2, 3)
    lua_func("function(x) x[1] = 99 end", "&N")(x)
    expect_identical(x[1], 99)

    # &L = byref logical
    y = c(TRUE, FALSE, TRUE)
    lua_func("function(x) x[1] = false end", "&L")(y)
    expect_identical(y[1], FALSE)
})

test_that("'X' argcode pushes SEXP cdata directly", {
    lua("ffi = require('ffi'); R = require('R')")

    is_sexp = lua_func("function(x) return ffi.istype(R.sexp, x) end", "S")
    expect_true(is_sexp(1L))
    expect_true(is_sexp(c(1.5, 2.5)))
    expect_true(is_sexp("hello"))
    expect_true(is_sexp(list(a = 1)))
    expect_true(is_sexp(NULL))

    # Pointer round-trips identically
    identity_x = lua_func("function(x) return x end", "S")
    v = c(pi, exp(1), sqrt(2))
    expect_identical(identity_x(v), v)
    s = c("a", "b", "c")
    expect_identical(identity_x(s), s)
    expect_identical(identity_x(list(a = 1, b = 2)), list(a = 1, b = 2))
})

test_that("environment argcode works", {
    lua("R = require('R')")
    f = lua_func("function(e) return luajr.is_environment(e) end", "E")
    expect_true(f(globalenv()))
    expect_error(f(1:5))
})

test_that("function argcode works", {
    f = lua_func("function(fn) return luajr.is_rfunction(fn) end", "F")
    expect_true(f(mean))
    expect_error(f(1:5))
})

test_that("native function argcode wraps R function as Lua function", {
    # $F with an R function: passed value has type() == "function" and is callable
    expect_identical(lua_func("function(fn) return type(fn) end", "$F")(mean), "function")

    # Calling the wrapped R function from Lua returns the R result
    expect_identical(lua_func("function(fn) return fn(luajr.numeric({1, 2, 3, 4, 5})) end", "$F")(mean), 3)

    # Multiple args
    expect_identical(lua_func("function(fn) return fn(2, 3) end", "$F")(`+`), 5)
})

test_that("native function argcode passes Lua function externalptr as-is", {
    # First make a Lua function and round-trip it through R as externalptr
    make_doubler = lua_func("function() return function(x) return x * 2 end end")
    g_ptr = make_doubler()
    expect_identical(class(g_ptr), "externalptr")

    # Pass that externalptr back in with $F — Lua should see it as a function
    expect_identical(lua_func("function(fn) return type(fn) end", "$F")(g_ptr), "function")
    expect_identical(lua_func("function(fn) return fn(21) end", "$F")(g_ptr), 42)
})

test_that("native function argcode rejects non-functions", {
    f = lua_func("function(fn) return fn end", "$F")
    expect_error(f(1:5))
    expect_error(f("hello"))
    expect_error(f(list()))
})

test_that("pointer argcode works", {
    L = lua_open()

    # P pushes as lightuserdata
    expect_identical(lua_func("function(x) return type(x) end", "P")(L), "userdata")

    # P round-trips external pointer
    expect_identical(lua_func("function(x) return x end", "P")(L), L)

    # P rejects non-external-pointer
    expect_error(lua_func("function(x) return x end", "P")(1:5))

    # . (value) with external pointer also gives lightuserdata
    expect_identical(lua_func("function(x) return type(x) end", ".")(L), "userdata")
})

test_that("returning a Lua function works", {
    make_doubler = lua_func("function() return function(x) return x * 2 end end")
    g_ptr = make_doubler()
    expect_identical(class(g_ptr), "externalptr")
    g = lua_func(g_ptr, "$N")
    expect_identical(g(21), 42)

    make_adder = lua_func("function(n) return function(x) return x + n end end", "$N")
    add3 = lua_func(make_adder(3), "$N")
    expect_identical(add3(10), 13)
    expect_identical(add3(0), 3)
})

test_that("returning luajr vector cdata works", {
    expect_identical(lua_func("function() local v = luajr.logical(3); v[1]=true; v[2]=false; v[3]=true; return v end")(),
        c(TRUE, FALSE, TRUE))
    expect_identical(lua_func("function() local v = luajr.integer(2); v[1]=10; v[2]=20; return v end")(),
        c(10L, 20L))
    expect_identical(lua_func("function() local v = luajr.numeric(3); v[1]=1.5; v[2]=2.5; v[3]=3.5; return v end")(),
        c(1.5, 2.5, 3.5))
    expect_identical(lua_func("function() local v = luajr.character(2); v[1]='a'; v[2]='b'; return v end")(),
        c("a", "b"))

    # Shrink case (n < c after push_back)
    f = lua_func("function()
        local v = luajr.numeric()
        for i = 1, 5 do v:push_back(i * 10) end
        return v
    end")
    expect_identical(f(), c(10, 20, 30, 40, 50))

    # Empty vector
    expect_identical(lua_func("function() return luajr.integer() end")(), integer(0))
})

test_that("multiple argcodes work", {
    # Two args with different types
    f = lua_func("function(x, y) return x[1] + y end", "N, $I")
    expect_identical(f(c(10, 20), 5L), 15)

    # Mixed: byref vector + native scalar
    f = lua_func("function(x, k) for i = 1, #x do x[i] = x[i] * k end end", "&N, $N")
    x = c(1, 2, 3)
    f(x, 10)
    expect_identical(x, c(10, 20, 30))
})

test_that("argcode recycling works", {
    # Single argcode applied to multiple args
    f = lua_func("function(x, y, z) return x[1] + y[1] + z[1] end", "N")
    expect_identical(f(c(1), c(2), c(3)), 6)
})

test_that("passing NA in vectors round-trips correctly", {
    expect_identical(lua_func("function(x) return x end", ".")(NA), NA)
    expect_identical(lua_func("function(x) return x end", ".")(NA_real_), NA_real_)
    expect_identical(lua_func("function(x) return x end", ".")(NA_integer_), NA_integer_)
    expect_identical(lua_func("function(x) return x end", ".")(NA_character_), NA_character_)

    expect_identical(lua_func("function(x) return x end", "&.")(NA), NA)
    expect_identical(lua_func("function(x) return x end", "&.")(NA_real_), NA_real_)
    expect_identical(lua_func("function(x) return x end", "&.")(NA_integer_), NA_integer_)
    expect_identical(lua_func("function(x) return x end", "&.")(NA_character_), NA_character_)
})

test_that("long-form argcodes work", {
    expect_identical(lua_func("function(x) return x end", "numeric")(c(1, 2, 3)), c(1, 2, 3))
    expect_identical(lua_func("function(x) return x end", "$numeric")(1.5), 1.5)
    expect_identical(lua_func("function(x) return x end", "&numeric")(c(1, 2)), c(1, 2))
    expect_identical(lua_func("function(x, y) return x[1] + y end", "numeric, $integer")(c(10), 5L), 15)
})
