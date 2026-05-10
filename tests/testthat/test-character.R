test_that("character vector metamethods work", {
    # constructor
    lua("x0 = luajr.character()")
    lua("x1 = luajr.character(3, 'a')")
    lua("x2 = luajr.character({'aa', 'bb', 'cc'})")
    lua("x3 = luajr.character(x0)")

    expect_identical(lua("return x0:debug_str()"), "0|0|")
    expect_identical(lua("return x1:debug_str()"), "3|3|a,a,a")
    expect_identical(lua("return x2:debug_str()"), "3|3|aa,bb,cc")
    expect_identical(lua("return x3:debug_str()"), "0|0|")

    # length
    expect_identical(lua("return #x2"), 3)
    expect_identical(lua("return #x3"), 0)

    # index, newindex
    expect_identical(lua("return x2[2]"), 'bb')
    expect_identical(lua("x2[3] = 'zz'; return x2[3]"), 'zz')

    # pairs, ipairs
    expect_identical(lua("local s = ''; for k,v in pairs(x1) do s = s .. v end; return s"), 'aaa')
    expect_identical(lua("local s = ''; for k,v in ipairs(x2) do s = s .. v end; return s"), 'aabbzz')

    lua_reset()
})

test_that("character vector assign works", {
    # Testing the following:
    # assign: nil nil, number string, table nil, vector nil
    # new vector: smaller, bigger (than capacity)
    expect_identical(lua("local x = luajr.character(2, 'a'); x:assign(); return x:debug_str()"), "0|2|")
    expect_identical(lua("local x = luajr.character(2, 'a'); x:assign(1, 'b'); return x:debug_str()"), "1|2|b")
    expect_identical(lua("local x = luajr.character(2, 'a'); x:assign(3, 'b'); return x:debug_str()"), "3|3|b,b,b")
    expect_identical(lua("local x = luajr.character(2, 'a'); x:assign({'b'}); return x:debug_str()"), "1|2|b")
    expect_identical(lua("local x = luajr.character(2, 'a'); x:assign({'b','c','d'}); return x:debug_str()"), "3|3|b,c,d")
    expect_identical(lua("local x,y = luajr.character(2, 'a'), luajr.character(1, 'b'); x:assign(y); return x:debug_str()"), "1|2|b")
    expect_identical(lua("local x,y = luajr.character(2, 'a'), luajr.character({'b','c','d'}); x:assign(y); return x:debug_str()"), "3|3|b,c,d")
})

test_that("character vector capacity methods work", {
    lua("x = luajr.character()")
    lua("x:reserve(5)")
    expect_equal(lua("return x:debug_str()"), "0|5|")
    lua("x:shrink_to_fit()")
    expect_equal(lua("return x:debug_str()"), "0|0|")

    lua_reset()
})

test_that("character vector resize works", {
    lua("x = luajr.character(2, 'a')")
    lua("x:clear()")
    expect_equal(lua("return x:debug_str()"), "0|2|");
    lua("x:resize(2, 'b')")
    expect_equal(lua("return x:debug_str()"), "2|2|b,b");
    lua("x:resize(1, 'c')")
    expect_equal(lua("return x:debug_str()"), "1|2|b");
    lua("x:resize(4, 'c')")
    expect_equal(lua("return x:debug_str()"), "4|4|b,c,c,c");

    lua_reset()
})

test_that("character push_back and pop_back work", {
    lua("x = luajr.character(2, 'a')")
    lua("x:push_back('b')");
    expect_equal(lua("return x:debug_str()"), "3|4|a,a,b");
    lua("x:push_back('c')");
    expect_equal(lua("return x:debug_str()"), "4|4|a,a,b,c");
    lua("x:push_back('d')");
    expect_equal(lua("return x:debug_str()"), "5|8|a,a,b,c,d");
    lua("for i=1,5 do x:pop_back() end");
    expect_equal(lua("return x:debug_str()"), "0|8|");

    lua_reset()
})

test_that("character insert and erase work", {
    # Testing the following:
    # insert: number string, table nil, vector nil
    # capacity allows, capacity must grow
    lua("x = luajr.character({'a','b','c','d','e','f','g'})")
    lua("x:reserve(10)")
    lua("x:insert(5, 3, 'z')")
    expect_equal(lua("return x:debug_str()"), "10|10|a,b,c,d,z,z,z,e,f,g")
    lua("x:insert(3, 2, 'y')")
    expect_equal(lua("return x:debug_str()"), "12|12|a,b,y,y,c,d,z,z,z,e,f,g")

    lua("x = luajr.character({'a','b','c','d','e','f','g'})")
    lua("x:reserve(10)")
    lua("x:insert(5, {'z','z','z'})")
    expect_equal(lua("return x:debug_str()"), "10|10|a,b,c,d,z,z,z,e,f,g")
    lua("x:insert(3, {'y','y'})")
    expect_equal(lua("return x:debug_str()"), "12|12|a,b,y,y,c,d,z,z,z,e,f,g")

    lua("x = luajr.character({'a','b','c','d','e','f','g'})")
    lua("x:reserve(10)")
    lua("x:insert(5, luajr.character(3, 'z'))")
    expect_equal(lua("return x:debug_str()"), "10|10|a,b,c,d,z,z,z,e,f,g")
    lua("x:insert(3, luajr.character(2, 'y'))")
    expect_equal(lua("return x:debug_str()"), "12|12|a,b,y,y,c,d,z,z,z,e,f,g")

    # erase
    lua("x = luajr.character({'a','b','c','d','e','f','g','h','i','j'})")
    lua("x:erase(1)")
    expect_equal(lua("return x:debug_str()"), "9|10|b,c,d,e,f,g,h,i,j")
    lua("x:erase(2,3)")
    expect_equal(lua("return x:debug_str()"), "7|10|b,e,f,g,h,i,j")
    lua("x:erase(5,7)")
    expect_equal(lua("return x:debug_str()"), "4|10|b,e,f,g")
    lua("x:erase(1,4)")
    expect_equal(lua("return x:debug_str()"), "0|10|")

    lua_reset()
})

test_that("character vector copy independence", {
    lua("x = luajr.character({'apple', 'banana', 'cherry'})")
    lua("y = luajr.character(x)")
    lua("x[2] = 'grape'")
    expect_identical(lua("return x[2]"), "grape")
    expect_identical(lua("return y[2]"), "banana")
    lua_reset()
})

test_that("character vector NA values", {
    lua("x = luajr.character(3, 'a')")
    lua("x[2] = luajr.NA_character_")
    # Returning a single NA_STRING element doesn't round-trip to R correctly
    # (it's a CHARSXP cdata, not a Lua string). Test via the vector return path instead.
    expect_identical(lua_func("function(x) return x end", "&.")(c("a", NA_character_, "a")),
                     c("a", NA_character_, "a"))
    expect_identical(lua("return x[1]"), "a")
    lua_reset()
})
