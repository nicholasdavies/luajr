test_that("functions work", {
    # Extract the Lua function table.concat(table, sep) which creates a string
    # from a table with separator sep.
    table.concat = lua_func("table.concat")
    expect_equal(table.concat(list("A", 1), "/"), "A/1")
})

test_that("args codes work", {
    # I am not extensively documenting these now because I am going to overhaul
    # args codes in the near future. This is a note that I should document the
    # tests when I do.
    # NULL
    expect_equal(lua_func("type", "s")(NULL), "nil")
    expect_equal(lua_func("type", "a")(NULL), "nil")
    expect_equal(lua_func("type", "t")(NULL), "nil")
    expect_equal(lua_func("type", "^")(NULL), "nil") # '^' doesn't mean anything

    # length-0 vector
    expect_equal(lua_func("type", "s")(numeric(0)), "nil")
    expect_equal(lua_func("type", "a")(character(0)), "nil")
    expect_equal(lua_func("type", "t")(logical(0)), "nil")
    expect_equal(lua_func("type", "^")(list()), "nil")

    lua('tellme = function(x)
        if type(x) == "table" then
            str = "["
            for k,v in pairs(x) do
                str = str .. tostring(k) .. " = " .. tellme(v) .. "; "
            end
            return string.sub(str, 1, -3) .. "]"
        end
        return tostring(x)
    end')

    # length-1 vector
    expect_equal(lua_func("tellme", "s")(c(a = TRUE)), "true")
    expect_equal(lua_func("tellme", "a")(c(a = 1.34)), "[1 = 1.34]")
    expect_equal(lua_func("tellme", "t")(c(a = "Hi")), "[a = Hi]")

    # length > 1 vector
    expect_equal(lua_func("tellme", "s")(c(TRUE, FALSE)), "[1 = true; 2 = false]")

    # list
    expect_equal(lua_func("tellme", "s")(list(list(1, 2), 3)),
        "[1 = [1 = 1; 2 = 2]; 2 = 3]")
    expect_equal(lua_func("tellme", "t")(list(list(1, 2), 3)),
        "[1 = [1 = [1 = 1]; 2 = [1 = 2]]; 2 = [1 = 3]]")
})
