test_that("states can be opened", {
    # Open a new state and check its type
    L2 = lua_open()
    expect_type(L2, "externalptr")

    # Verify variables can be set within a state.
    lua("a = 2", L = L2)
    expect_identical(lua("return a", L = L2), 2)
})

test_that("states are independent", {
    # Set the same variable in two different states and verify independence
    L2 = lua_open()

    lua("a = 2")
    lua("a = 3", L = L2)

    expect_identical(lua("return a"), 2)
    expect_identical(lua("return a", L = L2), 3)
})

test_that("state pointers can be shallow copied", {
    # Set animal = "dog" in new state L2
    L2 = lua_open()
    lua("animal = 'dog'", L = L2)

    # Shallow copy L2 to L3
    L3 = L2

    # Verify set in L3, even after attempt to erase L2
    rm(L2)
    gc()
    expect_identical(lua("return animal", L = L3), "dog")
})

test_that("states can be reset", {
    # Reset the default state
    lua("animal = 'fish'")
    lua_reset()
    expect_null(lua("return animal"))

    # 'Reset' a created state
    L2 = lua_open()
    lua("animal = 'cat'", L = L2)
    L2 = lua_open()
    expect_null(lua("return animal"))
})
