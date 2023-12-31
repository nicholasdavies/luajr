library(luajr)

# TODO allow pass by reference into Lua (see devnotes)
# TODO lock (threadwise) on R operations from within Lua
# TODO make naming of luajr C api consistent (luajr_ prefix, etc)
# TODO C api: Check it is actually usable from C, or just call it a C++ api
# TODO document, including vignettes
# TODO as part of documentation, be thorough about how Lua types are returned to
# R. In particular note how all number keys of a table are ignored in particular
# value, regardless of whether positive, negative, non-integer, etc
# TODO fix no git available for .relver - see https://github.com/LuaJIT/LuaJIT/pull/1073
# TODO work through all of the r packages guide (1x2x3x4x5x 6x7x8x 9x10x11x12x 13x14x15x 16_17_18_19_)
# TODO once there is something to cite, usethis::use_citation()?
# TODO check if cpp11 is really needed; if not remove; if yes add to SystemRequirements (see R Packages 2e chpt 9.7) [needed for = delete]
# TODO link against the specific luajit lib that is built (???)

bench::mark(
    L <- lua_open()
) # 157 mis
# 123 mis

# parameter detection -- note with current version of LuaJIT, can only do this from Lua.
lua("f1 = function() end")
lua("f2 = function(a, b) end")
lua("f3 = function(a, b, c, ...) end")

lua("get_args = function(f)
    info = debug.getinfo(f)
    for i=1,info.nparams do
        print(debug.getlocal(f, i))
    end
    if info.isvararg then
        print('...')
    end
end")
lua("get_args(f1)")
lua("get_args(f2)")
lua("get_args(f3)")

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
# Have shown this in tests/testthat/test-C.R


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
