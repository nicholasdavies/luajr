test_that("luajr.list construction and basic ops", {
    lua("ffi = require('ffi'); R = require('R')")

    # Empty construction
    lua("x = luajr.list()")
    expect_identical(lua("return #x"), 0)
    expect_true(lua("return luajr.is_list(x)"))

    # push_back grows the list
    lua("x:push_back(1)")
    lua("x:push_back('hello')")
    lua("x:push_back(luajr.numeric({1, 2, 3}))")
    expect_identical(lua("return #x"), 3)

    # Indexed read returns a wrapped element. Reading an element of
    # an owned list yields an alias-mode wrapper around the element SEXP.
    expect_identical(lua("return x[1][1]"), 1)
    expect_identical(lua("return x[2][1]"), "hello")
    expect_identical(lua("return x[3][2]"), 2)

    # Whole list round-trips to an R list
    expect_identical(lua("return x"), list(1, "hello", c(1, 2, 3)))

    lua_reset()
})

test_that("luajr.list named element access via find/get/set", {
    lua("x = luajr.list()")

    # :set with a new name appends and adds the name
    lua("x:set('a', 10)")
    lua("x:set('b', 20)")
    expect_identical(lua("return #x"), 2)
    expect_identical(lua("return x:find('a')"), 1)
    expect_identical(lua("return x:find('b')"), 2)
    expect_null(lua("return x:find('c')"))

    # :get returns the wrapped element (or nil)
    expect_identical(lua("return x:get('a')[1]"), 10)
    expect_identical(lua("return x:get('b')[1]"), 20)
    expect_null(lua("return x:get('c')"))

    # :set with an existing name overwrites at that position
    lua("x:set('a', 99)")
    expect_identical(lua("return x:get('a')[1]"), 99)

    # Round-trip preserves names
    expect_identical(lua("return x"), list(a = 99, b = 20))

    lua_reset()
})

test_that("luajr.list integer index assignment overwrites in place", {
    lua("x = luajr.list()")
    lua("x:push_back(1); x:push_back(2); x:push_back(3)")

    # Overwrite existing positions
    lua("x[1] = 'one'")
    lua("x[3] = luajr.integer({100, 200})")

    expect_identical(lua("return x[1][1]"), "one")
    expect_identical(lua("return x[2][1]"), 2)
    expect_identical(lua("return x[3][2]"), 200)

    lua_reset()
})

test_that("luajr.list round-trips R lists by reference and value", {
    identity_r = lua_func("function(x) return x end", "r")
    identity_v = lua_func("function(x) return x end", "v")

    expect_identical(identity_r(list(1, 2, 3)),               list(1, 2, 3))
    expect_identical(identity_v(list(1, 2, 3)),               list(1, 2, 3))
    expect_identical(identity_r(list(a = 1, b = 2, c = 3)),   list(a = 1, b = 2, c = 3))
    expect_identical(identity_v(list(a = 1, b = 2, c = 3)),   list(a = 1, b = 2, c = 3))
    expect_identical(identity_r(list(a = 1, 2, b = 3)),       list(a = 1, 2, b = 3))
})

test_that("luajr.list :set_attr sets attributes on the underlying SEXP", {
    lua("x = luajr.list()")
    lua("x:push_back(1); x:push_back(2)")
    lua("x:set_attr('class', luajr.character({'mylist'}))")

    x = lua("return x")
    expect_identical(class(x), "mylist")

    lua_reset()
})
