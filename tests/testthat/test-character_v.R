test_that("character vector metamethods work", {
    # constructor
    lua("x0 = luajr.character()")
    lua("x1 = luajr.character(3, 'a')")
    lua("x2 = luajr.character({1,2,3})")
    lua("x3 = luajr.character(x0)")

    expect_identical(lua("return x0:debug_str()"), "0|0|")
    expect_identical(lua("return x1:debug_str()"), "3|3|a,a,a")
    expect_identical(lua("return x2:debug_str()"), "3|3|1,2,3")
    expect_identical(lua("return x3:debug_str()"), "0|0|")

    # length
    expect_identical(lua("return #x2"), 3)
    expect_identical(lua("return #x3"), 0)

    # index, newindex
    expect_identical(lua("return x2[2]"), '2')
    expect_identical(lua("x2[3] = 42; return x2[3]"), '42')

    # pairs, ipairs
    expect_identical(lua("local s = ''; for k,v in pairs(x1) do s = s .. v end; return s"), 'aaa')
    expect_identical(lua("local s = ''; for k,v in ipairs(x2) do s = s .. v end; return s"), '1242')

    lua_reset()
})

test_that("character vector assign works", {
    # Testing the following:
    # assign: nil nil, number number, table nil, vector nil
    # new vector: smaller, bigger (than capacity)
    expect_identical(lua("local x = luajr.character(2, 0); x:assign(); return x:debug_str()"), "0|0|")
    expect_identical(lua("local x = luajr.character(2, 0); x:assign(1, 1); return x:debug_str()"), "1|1|1")
    expect_identical(lua("local x = luajr.character(2, 0); x:assign(3, 1); return x:debug_str()"), "3|3|1,1,1")
    expect_identical(lua("local x = luajr.character(2, 0); x:assign({1}); return x:debug_str()"), "1|1|1")
    expect_identical(lua("local x = luajr.character(2, 0); x:assign({1,2,3}); return x:debug_str()"), "3|3|1,2,3")
    expect_identical(lua("local x,y = luajr.character(2, 0), luajr.character(1, 1); x:assign(y); return x:debug_str()"), "1|1|1")
    expect_identical(lua("local x,y = luajr.character(2, 0), luajr.character({1,2,3}); x:assign(y); return x:debug_str()"), "3|3|1,2,3")
})

test_that("character vector capacity methods work", {
    lua("x = luajr.character()")
    lua("x:reserve(5)")
    expect_equal(lua("return x:debug_str()"), "0|0|")
    lua("x:shrink_to_fit()")
    expect_equal(lua("return x:debug_str()"), "0|0|")

    lua_reset()
})

test_that("character vector resize works", {
    lua("x = luajr.character(2, 0)")
    lua("x:clear()")
    expect_equal(lua("return x:debug_str()"), "0|0|");
    lua("x:resize(2, 1)")
    expect_equal(lua("return x:debug_str()"), "2|2|1,1");
    lua("x:resize(1, 3)")
    expect_equal(lua("return x:debug_str()"), "1|1|1");
    lua("x:resize(4, 3)")
    expect_equal(lua("return x:debug_str()"), "4|4|1,3,3,3");

    lua_reset()
})

test_that("character push_back and pop_back work", {
    lua("x = luajr.character(2, 0)")
    lua("x:push_back(1)");
    expect_equal(lua("return x:debug_str()"), "3|3|0,0,1");
    lua("x:push_back(2)");
    expect_equal(lua("return x:debug_str()"), "4|4|0,0,1,2");
    lua("x:push_back(3)");
    expect_equal(lua("return x:debug_str()"), "5|5|0,0,1,2,3");
    lua("for i=1,5 do x:pop_back() end");
    expect_equal(lua("return x:debug_str()"), "0|0|");

    lua_reset()
})

test_that("character insert and erase work", {
    # Testing the following:
    # insert: number number, table nil, vector nil
    # capacity allows, capacity must grow
    lua("x = luajr.character({1,2,3,4,5,6,7})")
    lua("x:reserve(10)")
    lua("x:insert(5, 3, 9)")
    expect_equal(lua("return x:debug_str()"), "10|10|1,2,3,4,9,9,9,5,6,7")
    lua("x:insert(3, 2, 8)")
    expect_equal(lua("return x:debug_str()"), "12|12|1,2,8,8,3,4,9,9,9,5,6,7")

    lua("x = luajr.character({1,2,3,4,5,6,7})")
    lua("x:reserve(10)")
    lua("x:insert(5, {9,9,9})")
    expect_equal(lua("return x:debug_str()"), "10|10|1,2,3,4,9,9,9,5,6,7")
    lua("x:insert(3, {8,8})")
    expect_equal(lua("return x:debug_str()"), "12|12|1,2,8,8,3,4,9,9,9,5,6,7")

    lua("x = luajr.character({1,2,3,4,5,6,7})")
    lua("x:reserve(10)")
    lua("x:insert(5, luajr.character(3, 9))")
    expect_equal(lua("return x:debug_str()"), "10|10|1,2,3,4,9,9,9,5,6,7")
    lua("x:insert(3, luajr.character(2, 8))")
    expect_equal(lua("return x:debug_str()"), "12|12|1,2,8,8,3,4,9,9,9,5,6,7")

    # erase
    lua("x = luajr.character({1,2,3,4,5,6,7,8,9,10})")
    lua("x:erase(1)")
    expect_equal(lua("return x:debug_str()"), "9|9|2,3,4,5,6,7,8,9,10")
    lua("x:erase(2,3)")
    expect_equal(lua("return x:debug_str()"), "7|7|2,5,6,7,8,9,10")
    lua("x:erase(5,7)")
    expect_equal(lua("return x:debug_str()"), "4|4|2,5,6,7")
    lua("x:erase(1,4)")
    expect_equal(lua("return x:debug_str()"), "0|0|")

    lua_reset()
})
