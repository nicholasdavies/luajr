library(luajr)

# TODO writing R extensions: "They are unusual in their copying semantics in
# that when an R object is copied, the external pointer object is not
# duplicated. (For this reason external pointers should only be used as part of
# an object with normal semantics, for example an attribute or an element of a
# list.)" -- Lua states are just external pointers, is this a problem?
# TODO refactor names under src/:
#    C_api -> pushto;
#    internal -> luajr.cpp; put return/pass in pushto; register.cpp
#    lua_api -> ffi?
#    R_api -> state, run, func?
#    mvoe register.h to src/?
# TODO allow pass by reference into Lua (see devnotes)
# TODO lock (threadwise) on R operations from within Lua
# TODO make naming of luajr C api consistent (luajr_ prefix, etc)
# TODO C api: Check it is actually usable from C, or just call it a C++ api
# TODO document, including vignettes
# TODO fix no git available for .relver - see https://github.com/LuaJIT/LuaJIT/pull/1073
# TODO work through all of the r packages guide (1x2x3x4x5x 6x7x8x 9x10x11x12x 13_14_15_)
# TODO once there is something to cite, usethis::use_citation()?
# TODO check if cpp11 is really needed; if not remove; if yes add to SystemRequirements (see R Packages 2e chpt 9.7)

lua("a")
lua("a = 2")

L2 = lua_open()
lua("a = 4", L = L2)

lua("print(a)", L = NULL)
lua("print(a)", L = L2)
rm(L2)

# Copying of Lua states
L3 = lua_open()
lua("animal = 'dog'", L = L3)
L4 = L3
rm(L3)
rm(L4)
gc()
L3
lua("print(animal)", L = L3)
lua("print(animal)", L = L4)

# Testing args codes
lua('tellme = function(x, level)
    level = level or 0
    if type(x) == "table" then
        for k,v in pairs(x) do
            io.write(string.rep(" ", level) .. tostring(k) .. " => ")
            tellme(v, level + 1)
        end
    else
        print(x)
    end
end')

tellme = lua_func("tellme", args = "s")

c1 = TRUE
c2 = c(FALSE, TRUE, FALSE)
c3 = c(falz = FALSE, troo = TRUE)

tellme(c1)
tellme(c2)
tellme(c3)

tellme(list(1, 2, 3:6, list(4,5,6, list(7,8,9))))

names(c3)[2] = NA_character_
tellme(c3)

# OK so there are two use cases.

# NOTE this use case isn't ideal, we don't really want to be repeatedly calling
# small lua functions from within C++. This is contrary to the LuaJIT spirit.
# Repeatedly calling C is fine. But this should still be a potential use case
# although discouraged.
# In one (miasma models), basically I want to be able to pass lua function
# definitions (strings of lua code basically) to C++ functions defined within a
# package and use those to run logic. So for example, see local/use_case.cpp,
# and the function within would be called like this:
solve_ode_model(c(1.0, 1.0), "function(x) return { -x[1], x[2] } end", 0, 10, 0.1)

# For this I want to avoid just calling luajr::lua_func() on the supplied
# string, because that would incur the extra overhead of dropping into R,
# converting the parameters, converting the return values, etc.

# It would suffice to expose lua.h etc to users of this package.
# See https://stackoverflow.com/questions/20474303/using-c-function-from-other-package-in-rcpp

# OK - I have shown that this works (in principle) for cppFunction, sourceCpp
# and in the package context -- though it does need documentation.
# Have shown this in local/example_cppFunction.R, example_sourceCpp.R


# In another use case, I want to be able to execute some arbitrary lua code.
# Some uses of this:
lua("print('Hello World!')")
lua("
local x = 7.0
print(x^2)
")

# Capturing return values:
lua("return 6*2")
lua("return 'Hello ' .. 'world!'")

# Can also load external file, as in
lua(filename = "./local/test.lua")

# We can also declare functions in Lua that are callable from R code.
myfunc = lua_func("function(x) print('Hello world ' .. x .. '!') end")
myfunc("(bizarro)")

# Note also
lua("mysquare = function(x) return x^2 end")
square = lua_func("mysquare")
square(7)


# SPEED TEST
lua("ffi = require('ffi')")
lua("vdouble = ffi.typeof('double[?]')")

luatest = lua_func(
"function(steps, verbose)
    x = vdouble(16)
    for k = 1,steps do
        for i = 0,15 do
            x[i] = (i + 1) * 100
        end
        for j = 1,steps do
            for i = 0,15 do
                x[i] = x[i] * 0.99
            end
        end
    end
    if verbose then
        print(x[0]+x[1]+x[2]+x[3]+x[4]+x[5]+x[6]+x[7]+
            x[8]+x[9]+x[10]+x[11]+x[12]+x[13]+x[14]+x[15])
    end
end")

luatest_unroll = lua_func(
"function(steps)
    x = vdouble(16)
    for k = 1,steps do
        for i = 0,15 do
            x[i] = (i + 1) * 100
        end
        for j = 1,steps/8 do
            x[ 0] = x[ 0] * 0.99
            x[ 1] = x[ 1] * 0.99
            x[ 2] = x[ 2] * 0.99
            x[ 3] = x[ 3] * 0.99
            x[ 4] = x[ 4] * 0.99
            x[ 5] = x[ 5] * 0.99
            x[ 6] = x[ 6] * 0.99
            x[ 7] = x[ 7] * 0.99
            x[ 8] = x[ 8] * 0.99
            x[ 9] = x[ 9] * 0.99
            x[10] = x[10] * 0.99
            x[11] = x[11] * 0.99
            x[12] = x[12] * 0.99
            x[13] = x[13] * 0.99
            x[14] = x[14] * 0.99
            x[15] = x[15] * 0.99
            x[ 0] = x[ 0] * 0.99
            x[ 1] = x[ 1] * 0.99
            x[ 2] = x[ 2] * 0.99
            x[ 3] = x[ 3] * 0.99
            x[ 4] = x[ 4] * 0.99
            x[ 5] = x[ 5] * 0.99
            x[ 6] = x[ 6] * 0.99
            x[ 7] = x[ 7] * 0.99
            x[ 8] = x[ 8] * 0.99
            x[ 9] = x[ 9] * 0.99
            x[10] = x[10] * 0.99
            x[11] = x[11] * 0.99
            x[12] = x[12] * 0.99
            x[13] = x[13] * 0.99
            x[14] = x[14] * 0.99
            x[15] = x[15] * 0.99
            x[ 0] = x[ 0] * 0.99
            x[ 1] = x[ 1] * 0.99
            x[ 2] = x[ 2] * 0.99
            x[ 3] = x[ 3] * 0.99
            x[ 4] = x[ 4] * 0.99
            x[ 5] = x[ 5] * 0.99
            x[ 6] = x[ 6] * 0.99
            x[ 7] = x[ 7] * 0.99
            x[ 8] = x[ 8] * 0.99
            x[ 9] = x[ 9] * 0.99
            x[10] = x[10] * 0.99
            x[11] = x[11] * 0.99
            x[12] = x[12] * 0.99
            x[13] = x[13] * 0.99
            x[14] = x[14] * 0.99
            x[15] = x[15] * 0.99
            x[ 0] = x[ 0] * 0.99
            x[ 1] = x[ 1] * 0.99
            x[ 2] = x[ 2] * 0.99
            x[ 3] = x[ 3] * 0.99
            x[ 4] = x[ 4] * 0.99
            x[ 5] = x[ 5] * 0.99
            x[ 6] = x[ 6] * 0.99
            x[ 7] = x[ 7] * 0.99
            x[ 8] = x[ 8] * 0.99
            x[ 9] = x[ 9] * 0.99
            x[10] = x[10] * 0.99
            x[11] = x[11] * 0.99
            x[12] = x[12] * 0.99
            x[13] = x[13] * 0.99
            x[14] = x[14] * 0.99
            x[15] = x[15] * 0.99
            x[ 0] = x[ 0] * 0.99
            x[ 1] = x[ 1] * 0.99
            x[ 2] = x[ 2] * 0.99
            x[ 3] = x[ 3] * 0.99
            x[ 4] = x[ 4] * 0.99
            x[ 5] = x[ 5] * 0.99
            x[ 6] = x[ 6] * 0.99
            x[ 7] = x[ 7] * 0.99
            x[ 8] = x[ 8] * 0.99
            x[ 9] = x[ 9] * 0.99
            x[10] = x[10] * 0.99
            x[11] = x[11] * 0.99
            x[12] = x[12] * 0.99
            x[13] = x[13] * 0.99
            x[14] = x[14] * 0.99
            x[15] = x[15] * 0.99
            x[ 0] = x[ 0] * 0.99
            x[ 1] = x[ 1] * 0.99
            x[ 2] = x[ 2] * 0.99
            x[ 3] = x[ 3] * 0.99
            x[ 4] = x[ 4] * 0.99
            x[ 5] = x[ 5] * 0.99
            x[ 6] = x[ 6] * 0.99
            x[ 7] = x[ 7] * 0.99
            x[ 8] = x[ 8] * 0.99
            x[ 9] = x[ 9] * 0.99
            x[10] = x[10] * 0.99
            x[11] = x[11] * 0.99
            x[12] = x[12] * 0.99
            x[13] = x[13] * 0.99
            x[14] = x[14] * 0.99
            x[15] = x[15] * 0.99
            x[ 0] = x[ 0] * 0.99
            x[ 1] = x[ 1] * 0.99
            x[ 2] = x[ 2] * 0.99
            x[ 3] = x[ 3] * 0.99
            x[ 4] = x[ 4] * 0.99
            x[ 5] = x[ 5] * 0.99
            x[ 6] = x[ 6] * 0.99
            x[ 7] = x[ 7] * 0.99
            x[ 8] = x[ 8] * 0.99
            x[ 9] = x[ 9] * 0.99
            x[10] = x[10] * 0.99
            x[11] = x[11] * 0.99
            x[12] = x[12] * 0.99
            x[13] = x[13] * 0.99
            x[14] = x[14] * 0.99
            x[15] = x[15] * 0.99
            x[ 0] = x[ 0] * 0.99
            x[ 1] = x[ 1] * 0.99
            x[ 2] = x[ 2] * 0.99
            x[ 3] = x[ 3] * 0.99
            x[ 4] = x[ 4] * 0.99
            x[ 5] = x[ 5] * 0.99
            x[ 6] = x[ 6] * 0.99
            x[ 7] = x[ 7] * 0.99
            x[ 8] = x[ 8] * 0.99
            x[ 9] = x[ 9] * 0.99
            x[10] = x[10] * 0.99
            x[11] = x[11] * 0.99
            x[12] = x[12] * 0.99
            x[13] = x[13] * 0.99
            x[14] = x[14] * 0.99
            x[15] = x[15] * 0.99
        end
    end
    if verbose then
        print(x[0]+x[1]+x[2]+x[3]+x[4]+x[5]+x[6]+x[7]+
            x[8]+x[9]+x[10]+x[11]+x[12]+x[13]+x[14]+x[15])
    end
end")

cpptest = Rcpp::cppFunction(
"void cpptest(unsigned int steps, bool verbose) {
    double* x = new double[16];

    for (unsigned int k = 0; k < steps; ++k)
    {
        for (unsigned int i = 0; i < 16; ++i)
            x[i] = 100 * (i + 1);

        for (unsigned int j = 0; j < steps; ++j)
        {
            for (unsigned int i = 0; i < 16; ++i)
            {
                x[i] = x[i] * 0.99;
            }
        }
    }

    if (verbose)
        Rcpp::Rcout << x[0]+x[1]+x[2]+x[3]+x[4]+x[5]+x[6]+x[7]+
            x[8]+x[9]+x[10]+x[11]+x[12]+x[13]+x[14]+x[15] << '\\n';

    delete[] x;
}")

rtest1 = function(steps, verbose)
{
    x = numeric(16);

    for (k in 1:steps) {
        for (i in 1:16) {
            x[i] = 100 * i;
        }

        for (j in 1:steps) {
            for (i in 1:16) {
                x[i] = x[i] * 0.99;
            }
        }
    }

    if (verbose) {
        print(sum(x))
    }
}

rtest2 = function(steps, verbose)
{
    x = numeric(16);

    for (k in 1:steps) {
        for (i in 1:16) {
            x[i] = 100 * i;
        }

        for (j in 1:steps) {
            x = x * 0.99;
        }
    }

    if (verbose) {
        print(sum(x))
    }
}

system.time(luatest(5000, TRUE))  # .3s
system.time(luatest_unroll(5000, TRUE))  # .07s
system.time(cpptest(5000, TRUE))  # .04s
system.time(rtest1(5000, TRUE))   # 40s
system.time(rtest2(5000, TRUE))   # 3s

bench::mark(luatest(500, FALSE), min_time = 5)
bench::mark(luatest_unroll(500, FALSE), min_time = 5)
bench::mark(cpptest(500, FALSE), min_time = 5)
bench::mark(rtest1(500, FALSE), min_time = 5)
bench::mark(rtest2(500, FALSE), min_time = 5)
