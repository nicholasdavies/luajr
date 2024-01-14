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
    expect_identical(lua_func("type", "s")(L), "userdata")

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

    # Check NA
    # TODO none of these work! need to implement special behaviour for the 's'
    # types.
    # lua_func("function(x) return x end", "s")(NA) # note: plain NA is class logical
    # lua_func("function(x) return x end", "s")(NA_real_)
    # lua_func("function(x) return x end", "s")(NA_integer_) # note: under 's',
    # both integer and real get turned into lua_Number, so I think need to go
    # through and manually convert any NA_integer_ in an integer to an NA_real_
    # lua_func("function(x) return x end", "s")(NA_character_)

})
