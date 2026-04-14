test_that("functions work", {
    # Extract the Lua function table.concat(table, sep) which creates a string
    # from a table with separator sep.
    table.concat = lua_func("table.concat")
    expect_equal(table.concat(list("A", 1), "/"), "A/1")
})

test_that("pass by reference works", {
    identity = lua_func("function(x) return x end", "r")
    expect_identical(identity(c(TRUE, FALSE, FALSE)), c(TRUE, FALSE, FALSE))
    expect_identical(identity(rep(0L, 10)), rep(0L, 10))
    expect_identical(identity(pi), pi)
    expect_identical(identity(letters), letters)
    expect_identical(identity(list(a = 1, b = pi, letters)), list(a = 1, b = pi, letters))
    expect_null(identity(NULL))

    # Pass and modify
    expect_identical(lua_func("function(x) x[1] = true return x end", "r")(c(FALSE, FALSE, FALSE)), c(TRUE, FALSE, FALSE))
    expect_identical(lua_func("function(x) x[1] = 0 return x end", "r")(c(1L, rep(0L, 9))), rep(0L, 10))
    expect_identical(lua_func("function(x) x[1] = x[1] + 1 return x end", "r")(pi - 1), pi)
    expect_identical(lua_func("function(x) x[1] = 'a' return x end", "r")(c('b', 'b', 'c')), letters[1:3])
    expect_identical(lua_func("function(x) x.b[1] = math.pi return x end", "r")(list(a = 1, b = 0, letters)), list(a = 1, b = pi, letters))
})

test_that("pass by value works", {
    identity = lua_func("function(x) return x end", "v")
    expect_identical(identity(c(TRUE, FALSE, FALSE)), c(TRUE, FALSE, FALSE))
    expect_identical(identity(rep(0L, 10)), rep(0L, 10))
    expect_identical(identity(pi), pi)
    expect_identical(identity(letters), letters)
    expect_identical(identity(list(a = 1, b = pi, letters)), list(a = 1, b = pi, letters))
    expect_null(identity(NULL))

    # Pass and modify
    expect_identical(lua_func("function(x) x[1] = true return x end", "v")(c(FALSE, FALSE, FALSE)), c(TRUE, FALSE, FALSE))
    expect_identical(lua_func("function(x) x[1] = 0 return x end", "v")(c(1L, rep(0L, 9))), rep(0L, 10))
    expect_identical(lua_func("function(x) x[1] = x[1] + 1 return x end", "v")(pi - 1), pi)
    expect_identical(lua_func("function(x) x[1] = 'a' return x end", "v")(c('b', 'b', 'c')), letters[1:3])
    expect_identical(lua_func("function(x) x.b[1] = math.pi return x end", "v")(list(a = 1, b = 0, letters)), list(a = 1, b = pi, letters))
})

# In testing argument passing, check the 7 R types that luajr can pass to Lua:
# NULL, logical, integer, numeric, character, list, externalptr
test_that("pass by simplify works", {
    L = lua_open()

    # Check type
    expect_identical(lua_func("type", "s")(NULL), "nil")
    expect_identical(lua_func("type", "s")(TRUE), "boolean")
    expect_identical(lua_func("type", "s")(111L), "number")
    expect_identical(lua_func("type", "s")(1.01), "number")
    expect_identical(lua_func("type", "s")("Hi"), "string")
    expect_identical(lua_func("type", "s")(list()), "table")
    # TODO: old C++ path pushed external pointers as lightuserdata so type() returned
    # "userdata". The Lua-side path returns a cdata void* (FFI cannot create
    # lightuserdata), so type() now returns "cdata". Restore "userdata" semantics
    # if/when a C helper is exposed.
    # Old C++ version
    expect_identical(lua_func("type", "s")(L), "userdata")
    # New Lua version
    # expect_identical(lua_func("type", "s")(L), "cdata")
    # END TODO
    expect_identical(lua_func("type", "s")(charToRaw("Hello")), "string")

    # Check values
    lua_identity = lua_func("function(x) return x end", "s")
    expect_null(lua_identity(NULL))
    expect_identical(lua_identity(TRUE), TRUE)
    expect_identical(lua_identity(FALSE), FALSE)
    expect_identical(lua_identity(-123L), -123.0) # no integer type in LuaJIT
    expect_identical(lua_identity(c(pi, exp(0), sqrt(2))), list(pi, exp(0), sqrt(2)))
    expect_identical(lua_identity("Christmas"), "Christmas")
    expect_identical(lua_identity(list()), list())
    expect_identical(lua_identity(list(1, b = list(c = 3))), list(1, b = list(c = 3)))
    expect_identical(lua_identity(L), L)
    expect_identical(lua_identity(as.raw(c(0,1,0))), as.raw(c(0,1,0)))

    # Check length enforce
    f_one = lua_func("tostring", "1")
    f_six = lua_func("table.concat", "6")
    expect_identical(f_one(NULL), "nil") # NULL always becomes nil regardless of code
    expect_identical(f_one(2L), "2")
    expect_identical(f_six(1:6), "123456")
    expect_error(f_one(1:6))
    expect_error(f_six(1:10))

    # Check 'a' versus 's'
    expect_identical(lua_func("function(x) return x end", "s")(1.5), 1.5)
    expect_identical(lua_func("function(x) return x[1] end", "a")(1.5), 1.5)
    expect_identical(lua_func("function(x) return x end", "a")(1.5), list(1.5))
    expect_error(lua_func("function(x) return x[1] end", "s")(1.5), "attempt to index local 'x' \\(a number value\\)")
})

test_that("returning a Lua function works", {
    # Function that returns a closure
    make_doubler = lua_func("function() return function(x) return x * 2 end end")
    g_ptr = make_doubler()
    expect_identical(class(g_ptr), "externalptr")
    g = lua_func(g_ptr)
    expect_identical(g(21), 42)

    # Closure capturing an upvalue
    make_adder = lua_func("function(n) return function(x) return x + n end end")
    add3 = lua_func(make_adder(3))
    expect_identical(add3(10), 13)
    expect_identical(add3(0), 3)
})

test_that("returning luajr vector cdata uses fast path (no pcall)", {
    # All four vector types should round-trip via the C-side fast path
    # (luajr_tryget_sexp_cdata in lj_luajr.c), which checks the cdata's
    # ctype and extracts the SEXP directly.

    # Exact-size case (n == c, no shrink needed)
    expect_identical(lua_func("function() local v = luajr.logical(3); v[1]=true; v[2]=false; v[3]=true; return v end")(),
        c(TRUE, FALSE, TRUE))
    expect_identical(lua_func("function() local v = luajr.integer(2); v[1]=10; v[2]=20; return v end")(),
        c(10L, 20L))
    expect_identical(lua_func("function() local v = luajr.numeric(3); v[1]=1.5; v[2]=2.5; v[3]=3.5; return v end")(),
        c(1.5, 2.5, 3.5))
    expect_identical(lua_func("function() local v = luajr.character(2); v[1]='a'; v[2]='b'; return v end")(),
        c("a", "b"))

    # Shrink case (n < c after push_back); SETLENGTH should truncate in place
    f = lua_func("function()
        local v = luajr.numeric()
        for i = 1, 5 do v:push_back(i * 10) end
        return v
    end")
    expect_identical(f(), c(10, 20, 30, 40, 50))

    # Empty vector still works
    expect_identical(lua_func("function() return luajr.integer() end")(), integer(0))
})

test_that("'x' argcode pushes SEXP cdata directly", {
    # Make ffi/R available
    lua("ffi = require('ffi'); R = require('R')")

    # The 'x' code should push the value as a cdata of type R.sexp,
    # using the fast path implemented in lj_luajr.c (luajr_push_sexp_cdata).
    is_sexp = lua_func("function(x) return ffi.istype(R.sexp, x) end", "x")
    expect_true(is_sexp(1L))
    expect_true(is_sexp(c(1.5, 2.5)))
    expect_true(is_sexp("hello"))
    expect_true(is_sexp(list(a = 1)))
    expect_true(is_sexp(NULL))

    # Pointer round-trips identically
    identity_x = lua_func("function(x) return x end", "x")
    v = c(pi, exp(1), sqrt(2))
    expect_identical(identity_x(v), v)
    s = c("a", "b", "c")
    expect_identical(identity_x(s), s)
    expect_identical(identity_x(list(a = 1, b = 2)), list(a = 1, b = 2))

    # Cross-state: a separate Lua state should also resolve SEXP correctly
    L = lua_open()
    lua("ffi = require('ffi'); R = require('R')", L = L)
    is_sexp_L = lua_func("function(x) return ffi.istype(R.sexp, x) end", "x", L = L)
    expect_true(is_sexp_L(1:5))
})

test_that("passing NA works", {
    expect_identical(lua_func("function(x) return x end", "v")(NA), NA) # note: plain NA is class logical
    expect_identical(lua_func("function(x) return x end", "v")(NA_real_), NA_real_)
    expect_identical(lua_func("function(x) return x end", "v")(NA_integer_), NA_integer_)
    expect_identical(lua_func("function(x) return x end", "v")(NA_character_), NA_character_)

    expect_identical(lua_func("function(x) return x end", "r")(NA), NA)
    expect_identical(lua_func("function(x) return x end", "r")(NA_real_), NA_real_)
    expect_identical(lua_func("function(x) return x end", "r")(NA_integer_), NA_integer_)
    expect_identical(lua_func("function(x) return x end", "r")(NA_character_), NA_character_)
})

