# Lua tables don't preserve insertion order for the hash part.
sort_list_names = function(x) {
    if (!is.list(x)) return(x)
    x = lapply(x, sort_list_names)
    nms = names(x)
    if (!is.null(nms) && all(nzchar(nms))) x = x[order(nms)]
    x
}

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
    identity_r = lua_func("function(x) return x end", "&V")
    identity_v = lua_func("function(x) return x end", "V")

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

test_that("luajr.list constructs nested lists from nested tables", {
    r = lua("return luajr.list({true, false, {true, 1, 0}})")
    expect_identical(r, list(TRUE, FALSE, list(TRUE, 1, 0)))

    lua_reset()
})

test_that("luajr.list nested list preserves names in sub-tables", {
    r = lua("return luajr.list({a = 1, b = {x = 10, y = 20}})")
    expect_identical(sort_list_names(r),
        sort_list_names(list(a = 1, b = list(x = 10, y = 20))))

    lua_reset()
})

test_that("luajr.list handles deeply nested tables", {
    r = lua("return luajr.list({1, {2, {3, {4, 5}}}})")
    expect_identical(r, list(1, list(2, list(3, list(4, 5)))))

    lua_reset()
})

test_that("luajr.list nested mixed types work", {
    r = lua("return luajr.list({'hello', {1, 2}, true, {{10}, 'inner'}})")
    expect_identical(r, list("hello", list(1, 2), TRUE, list(list(10), "inner")))

    lua_reset()
})

test_that("push_back of a Lua table converts to nested list", {
    lua("x = luajr.list()")
    lua("x:push_back('first')")
    lua("x:push_back({nested = true, value = 42})")
    r = lua("return x")
    expect_identical(sort_list_names(r),
        sort_list_names(list("first", list(nested = TRUE, value = 42))))

    lua_reset()
})

test_that("luajr.list:insert with no a, b is a no-op", {
    lua("l = luajr.list({1, 2, 3})")
    lua("l:insert(2)")
    expect_identical(lua("return l"), list(1, 2, 3))

    lua_reset()
})

test_that("luajr.list:insert from a bare SEXP", {
    lua("R = require('R')")
    lua("l = luajr.list({1, 4, 5})")
    lua("l:insert(2, luajr.list({2, 3}).s)")
    expect_identical(lua("return l"), list(1, 2, 3, 4, 5))

    lua_reset()
})

test_that("luajr.list:insert from a bare SEXP of wrong type errors", {
    expect_error(lua("luajr.list({1, 2}):insert(2, luajr.numeric({9}).s)"))

    lua_reset()
})

test_that("luajr.list:insert n copies of nil inserts NULLs", {
    lua("l = luajr.list({1, 4, 5})")
    lua("l:insert(2, 2)")  # insert 2 nils
    expect_identical(lua("return l"), list(1, NULL, NULL, 4, 5))

    lua_reset()
})
