test_that("lua() returns basic types", {
    # These are all testing luajr_tosexp() as well as lua()

    # Test return of scalar types nil, boolean, number, string
    expect_equal(lua("return glarblefleegle"), NULL)   # Undefined variable should equate to nil -> NULL
    expect_equal(lua("return 2 > 1"), TRUE)            # true condition -> TRUE
    expect_equal(lua("return math.pi*2"), 2*pi)        # also testing namespace lookup and math ops
    expect_equal(lua("return 'Hello ' .. 'World!'"), "Hello World!")

    # Test return of various tables
    # Empty table -> empty list
    expect_equal(lua("return {}"), list())
    # Array-like table -> array-like list
    expect_equal(lua("return {1, 2, 3}"), list(1, 2, 3))
    # Named table -> Named list, but keys can be in any order (hence mapequal)
    expect_mapequal(lua("return {a = 1, b = 2}"), list(a = 1, b = 2))
    # Table with both array and record parts -> array parts seem to always be first
    expect_equal(unname(lua("return {1, a = 2, 3, b = 4, 5}")[1:3]), list(1, 3, 5))

    # Test return of Lua types that we convert to a pointer (see luajr_tosexp)
    expect_type(lua("return print"), "externalptr")
})

test_that("lua() can run a file", {
    # Just checking override "filename" option in lua()
    # root2.lua returns math.sqrt(2)
    expect_equal(lua(filename = test_path("files", "root2.lua")), 2^0.5)
})

test_that("lua() produces errors", {
    # Identifier on its own is a parse error
    expect_error(lua("a"), "'=' expected near '<eof>'")
})
