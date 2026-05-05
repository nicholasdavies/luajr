test_that("construction preserves and omits names", {
    # empty, fill: no names
    expect_null(names(lua("return luajr.numeric()")))
    expect_null(names(lua("return luajr.numeric(3, 1)")))

    # copy from same-type vector with names
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    y = lua("return luajr.numeric(x)")
    expect_identical(names(y), c("a", "b", "c"))
    expect_identical(unname(y), c(10, 20, 30))

    # copy from same-type vector without names
    expect_null(names(lua("return luajr.numeric(luajr.numeric({1, 2}))")))

    # copy from Lua table: no names
    expect_null(names(lua("return luajr.numeric({1, 2, 3})")))

    lua_reset()
})

test_that("copy construction from cross-type vector preserves names", {
    lua("x = luajr.integer({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    # construct numeric from named integer (cross-type, vectorish path)
    y = lua("return luajr.numeric(x)")
    expect_identical(names(y), c("a", "b", "c"))
    expect_identical(unname(y), c(10, 20, 30))

    lua_reset()
})

test_that("assign fill clears names", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:assign(2, 0)")
    expect_null(names(lua("return x")))

    lua_reset()
})

test_that("assign fill clears names (allocate path)", {
    lua("x = luajr.numeric({1, 2})")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    lua("x:assign(10, 0)")
    expect_null(names(lua("return x")))

    lua_reset()
})

test_that("assign from same-type vector copies names", {
    # in-place (src fits in capacity)
    lua("x = luajr.numeric(5, 0)")
    lua("y = luajr.numeric({10, 20, 30})")
    lua("y:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:assign(y)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", "c"))
    expect_identical(unname(r), c(10, 20, 30))

    # allocate path (src larger than capacity)
    lua("x = luajr.numeric(1, 0)")
    lua("x:assign(y)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", "c"))

    lua_reset()
})

test_that("assign from same-type vector without names clears names", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("y = luajr.numeric({1, 2, 3})")
    lua("x:assign(y)")
    expect_null(names(lua("return x")))

    lua_reset()
})

test_that("assign from cross-type vector copies names", {
    lua("x = luajr.numeric(5, 0)")
    lua("y = luajr.integer({10, 20, 30})")
    lua("y:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:assign(y)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", "c"))
    expect_identical(unname(r), c(10, 20, 30))

    lua_reset()
})

test_that("assign from Lua table clears names", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:assign({1, 2})")
    expect_null(names(lua("return x")))

    lua_reset()
})

test_that("reserve preserves names", {
    lua("x = luajr.numeric({10, 20})")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    lua("x:reserve(10)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b"))
    expect_identical(unname(r), c(10, 20))

    lua_reset()
})

test_that("shrink_to_fit preserves names", {
    lua("x = luajr.numeric({10, 20})")
    lua("x:reserve(100)")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    lua("x:shrink_to_fit()")
    r = lua("return x")
    expect_identical(names(r), c("a", "b"))
    expect_identical(unname(r), c(10, 20))

    lua_reset()
})

test_that("clear drops names", {
    lua("x = luajr.numeric({10, 20})")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    lua("x:clear()")
    lua("x:push_back(99)")
    expect_null(names(lua("return x")))

    lua_reset()
})

test_that("push_back blanks new name slot", {
    lua("x = luajr.numeric({10, 20})")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    lua("x:push_back(30)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", ""))
    expect_identical(unname(r), c(10, 20, 30))

    lua_reset()
})

test_that("push_back after pop_back doesn't inherit ghost name", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:pop_back()")
    lua("x:push_back(99)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", ""))
    expect_identical(unname(r), c(10, 20, 99))

    lua_reset()
})

test_that("push_back triggers allocate and preserves names", {
    lua("x = luajr.numeric({10})")
    lua("x:set_attr('names', luajr.character({'a'}))")
    lua("x:push_back(20)")
    lua("x:push_back(30)")
    r = lua("return x")
    expect_identical(names(r), c("a", "", ""))
    expect_identical(unname(r), c(10, 20, 30))

    lua_reset()
})

test_that("pop_back shrinks without corrupting names", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:pop_back()")
    r = lua("return x")
    expect_identical(names(r), c("a", "b"))
    expect_identical(unname(r), c(10, 20))

    lua_reset()
})

test_that("insert fill shifts names, gap is blank (in-place)", {
    lua("x = luajr.numeric(5, 0)")
    lua("x:assign(luajr.numeric({10, 20, 30}))")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:insert(2, 2, 99)")
    r = lua("return x")
    expect_identical(names(r), c("a", "", "", "b", "c"))
    expect_identical(unname(r), c(10, 99, 99, 20, 30))

    lua_reset()
})

test_that("insert fill shifts names, gap is blank (allocate)", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:insert(2, 2, 99)")
    r = lua("return x")
    expect_identical(names(r), c("a", "", "", "b", "c"))
    expect_identical(unname(r), c(10, 99, 99, 20, 30))

    lua_reset()
})

test_that("insert from same-type vector copies source names into gap", {
    lua("x = luajr.numeric(10, 0)")
    lua("x:assign(luajr.numeric({10, 20, 30}))")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("y = luajr.numeric({88, 99})")
    lua("y:set_attr('names', luajr.character({'p', 'q'}))")
    lua("x:insert(2, y)")
    r = lua("return x")
    expect_identical(names(r), c("a", "p", "q", "b", "c"))
    expect_identical(unname(r), c(10, 88, 99, 20, 30))

    lua_reset()
})

test_that("insert from same-type vector without names leaves gap blank", {
    lua("x = luajr.numeric(10, 0)")
    lua("x:assign(luajr.numeric({10, 20, 30}))")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("y = luajr.numeric({88, 99})")
    lua("x:insert(2, y)")
    r = lua("return x")
    expect_identical(names(r), c("a", "", "", "b", "c"))
    expect_identical(unname(r), c(10, 88, 99, 20, 30))

    lua_reset()
})

test_that("insert from same-type vector (allocate path) copies source names", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("y = luajr.numeric({88, 99})")
    lua("y:set_attr('names', luajr.character({'p', 'q'}))")
    lua("x:insert(2, y)")
    r = lua("return x")
    expect_identical(names(r), c("a", "p", "q", "b", "c"))
    expect_identical(unname(r), c(10, 88, 99, 20, 30))

    lua_reset()
})

test_that("insert from cross-type vector copies source names", {
    lua("x = luajr.numeric(10, 0)")
    lua("x:assign(luajr.numeric({10, 20, 30}))")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("y = luajr.integer({88, 99})")
    lua("y:set_attr('names', luajr.character({'p', 'q'}))")
    lua("x:insert(2, y)")
    r = lua("return x")
    expect_identical(names(r), c("a", "p", "q", "b", "c"))
    expect_identical(unname(r), c(10, 88, 99, 20, 30))

    lua_reset()
})

test_that("insert from Lua table leaves gap blank", {
    lua("x = luajr.numeric(10, 0)")
    lua("x:assign(luajr.numeric({10, 20, 30}))")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:insert(2, {88, 99})")
    r = lua("return x")
    expect_identical(names(r), c("a", "", "", "b", "c"))
    expect_identical(unname(r), c(10, 88, 99, 20, 30))

    lua_reset()
})

test_that("insert at beginning and end shifts names correctly", {
    lua("x = luajr.numeric(10, 0)")
    lua("x:assign(luajr.numeric({10, 20, 30}))")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")

    # insert at beginning
    lua("x:insert(1, 1, 5)")
    r = lua("return x")
    expect_identical(names(r), c("", "a", "b", "c"))
    expect_identical(unname(r), c(5, 10, 20, 30))

    # insert at end (past last element)
    lua("x:insert(5, 1, 99)")
    r = lua("return x")
    expect_identical(names(r), c("", "a", "b", "c", ""))
    expect_identical(unname(r), c(5, 10, 20, 30, 99))

    lua_reset()
})

test_that("erase shifts names left (in-place, owned)", {
    lua("x = luajr.numeric({10, 20, 30, 40, 50})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c', 'd', 'e'}))")
    lua("x:erase(2, 3)")
    r = lua("return x")
    expect_identical(names(r), c("a", "d", "e"))
    expect_identical(unname(r), c(10, 40, 50))

    lua_reset()
})

test_that("erase single element shifts names (in-place)", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:erase(2)")
    r = lua("return x")
    expect_identical(names(r), c("a", "c"))
    expect_identical(unname(r), c(10, 30))

    lua_reset()
})

test_that("erase on alias vector shifts names (allocate path)", {
    identity_v = lua_func("function(x) x:erase(2); return x end", ".")
    x = c(a = 10, b = 20, c = 30)
    r = identity_v(x)
    expect_identical(names(r), c("a", "c"))
    expect_identical(unname(r), c(10, 30))

    lua_reset()
})

test_that("resize grow without val blanks new names", {
    lua("x = luajr.numeric({10, 20})")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    lua("x:resize(4)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", "", ""))
    expect_identical(r[1:2], c(a = 10, b = 20))

    lua_reset()
})

test_that("resize grow with val blanks new names", {
    lua("x = luajr.numeric({10, 20})")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    lua("x:resize(4, 99)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", "", ""))
    expect_identical(unname(r), c(10, 20, 99, 99))

    lua_reset()
})

test_that("resize shrink truncates names", {
    lua("x = luajr.numeric({10, 20, 30, 40})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c', 'd'}))")
    lua("x:resize(2)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b"))
    expect_identical(unname(r), c(10, 20))

    lua_reset()
})

test_that("detach preserves names", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:detach()")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", "c"))
    expect_identical(unname(r), c(10, 20, 30))

    lua_reset()
})

test_that("operations on unnamed vectors stay unnamed", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:push_back(40)")
    expect_null(names(lua("return x")))
    lua("x:insert(2, 1, 99)")
    expect_null(names(lua("return x")))
    lua("x:erase(3)")
    expect_null(names(lua("return x")))
    lua("x:pop_back()")
    expect_null(names(lua("return x")))
    lua("x:reserve(100)")
    expect_null(names(lua("return x")))
    lua("x:shrink_to_fit()")
    expect_null(names(lua("return x")))
    lua("x:resize(10)")
    expect_null(names(lua("return x")))

    lua_reset()
})

test_that("names work with character vectors", {
    lua("x = luajr.character({'hello', 'world'})")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    lua("x:push_back('!')")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", ""))
    expect_identical(unname(r), c("hello", "world", "!"))

    lua("x:insert(2, luajr.character({'mid'}))")
    r = lua("return x")
    expect_identical(names(r), c("a", "", "b", ""))
    expect_identical(unname(r), c("hello", "mid", "world", "!"))

    lua("x:erase(3)")
    r = lua("return x")
    expect_identical(names(r), c("a", "", ""))
    expect_identical(unname(r), c("hello", "mid", "!"))

    lua_reset()
})

test_that("names work with integer vectors", {
    lua("x = luajr.integer({1, 2, 3})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:erase(1)")
    r = lua("return x")
    expect_identical(names(r), c("b", "c"))
    expect_identical(unname(r), c(2L, 3L))

    lua("x:insert(1, 1, 0)")
    r = lua("return x")
    expect_identical(names(r), c("", "b", "c"))
    expect_identical(unname(r), c(0L, 2L, 3L))

    lua_reset()
})

test_that("names work with logical vectors", {
    lua("x = luajr.logical({true, false, true})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:pop_back()")
    lua("x:push_back(true)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", ""))
    expect_identical(unname(r), c(TRUE, FALSE, TRUE))

    lua_reset()
})

test_that("names work with list vectors", {
    lua("x = luajr.list()")
    lua("x:set('a', 10)")
    lua("x:set('b', 20)")
    lua("x:set('c', 30)")

    # erase middle element, names shift
    lua("x:erase(2)")
    r = lua("return x")
    expect_identical(names(r), c("a", "c"))
    expect_identical(r, list(a = 10, c = 30))

    # insert at beginning
    lua("x:insert(1, 1, 0)")
    r = lua("return x")
    expect_identical(names(r), c("", "a", "c"))

    lua_reset()
})

test_that("lua_func byref round-trip preserves names", {
    identity_r = lua_func("function(x) return x end", "&.")
    x = c(a = 1, b = 2, c = 3)
    expect_identical(identity_r(x), x)

    lua_reset()
})

test_that("lua_func alias round-trip preserves names", {
    identity_v = lua_func("function(x) return x end", ".")
    x = c(a = 1, b = 2, c = 3)
    expect_identical(identity_v(x), x)

    lua_reset()
})

test_that("combined insert-erase sequence keeps names consistent", {
    lua("x = luajr.numeric({10, 20, 30, 40, 50})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c', 'd', 'e'}))")

    # erase middle
    lua("x:erase(2, 3)")
    r = lua("return x")
    expect_identical(names(r), c("a", "d", "e"))

    # insert two at beginning
    lua("x:insert(1, 2, 0)")
    r = lua("return x")
    expect_identical(names(r), c("", "", "a", "d", "e"))

    # push_back
    lua("x:push_back(99)")
    r = lua("return x")
    expect_identical(names(r), c("", "", "a", "d", "e", ""))

    # pop_back twice, push_back once
    lua("x:pop_back()")
    lua("x:pop_back()")
    lua("x:push_back(77)")
    r = lua("return x")
    expect_identical(names(r), c("", "", "a", "d", ""))
    expect_identical(unname(r), c(0, 0, 10, 40, 77))

    lua_reset()
})

test_that("unname drops names on owned vector", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:unname()")
    expect_null(names(lua("return x")))
    expect_identical(lua("return x[2]"), 20)

    lua_reset()
})

test_that("unname on unnamed vector is a no-op", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:unname()")
    expect_null(names(lua("return x")))

    lua_reset()
})

test_that("unname on alias vector detaches and drops names", {
    identity_v = lua_func("function(x) x:unname(); return x end", ".")
    x = c(a = 1, b = 2, c = 3)
    r = identity_v(x)
    expect_null(names(r))
    expect_identical(unname(r), c(1, 2, 3))
    # original should be unchanged
    expect_identical(names(x), c("a", "b", "c"))

    lua_reset()
})

test_that("pop_back on alias preserves names", {
    identity_v = lua_func("function(x) x:pop_back(); return x end", ".")
    x = c(a = 10, b = 20, c = 30)
    r = identity_v(x)
    expect_identical(names(r), c("a", "b"))
    expect_identical(unname(r), c(10, 20))

    lua_reset()
})

test_that("clear on alias drops names", {
    identity_v = lua_func("function(x) x:clear(); x:push_back(99); return x end", ".")
    x = c(a = 10, b = 20)
    r = identity_v(x)
    expect_null(names(r))

    lua_reset()
})

test_that("assign cross-type vector without names clears names", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("y = luajr.integer({1, 2, 3})")
    lua("x:assign(y)")
    expect_null(names(lua("return x")))

    lua_reset()
})

test_that("assign cross-type vector copies names (allocate path)", {
    lua("x = luajr.numeric(1, 0)")
    lua("y = luajr.integer({10, 20, 30})")
    lua("y:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:assign(y)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b", "c"))
    expect_identical(unname(r), c(10, 20, 30))

    lua_reset()
})

test_that("assign Lua table clears names (allocate path)", {
    lua("x = luajr.numeric({1, 2})")
    lua("x:set_attr('names', luajr.character({'a', 'b'}))")
    lua("x:assign({10, 20, 30, 40, 50})")
    expect_null(names(lua("return x")))

    lua_reset()
})

test_that("__newindex on alias preserves names after COW", {
    identity_v = lua_func("function(x) x[2] = 99; return x end", ".")
    x = c(a = 10, b = 20, c = 30)
    r = identity_v(x)
    expect_identical(names(r), c("a", "b", "c"))
    expect_identical(unname(r), c(10, 99, 30))

    lua_reset()
})

test_that("erase first element shifts names", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:erase(1)")
    r = lua("return x")
    expect_identical(names(r), c("b", "c"))
    expect_identical(unname(r), c(20, 30))

    lua_reset()
})

test_that("erase last element preserves preceding names", {
    lua("x = luajr.numeric({10, 20, 30})")
    lua("x:set_attr('names', luajr.character({'a', 'b', 'c'}))")
    lua("x:erase(3)")
    r = lua("return x")
    expect_identical(names(r), c("a", "b"))
    expect_identical(unname(r), c(10, 20))

    lua_reset()
})
