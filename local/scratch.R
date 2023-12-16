library(luajr)

# TODO lock (threadwise) on R operations from within Lua

# TODO can't the lua code return some kind of ID which basically tells
# lua_func_call where to look for the return values? Then we could use normal
# Lua return statements. How about it returns some cdata? Note
# https://luajit.org/ext_ffi_semantics.html#gc

# TODO C api -- is it actually usable from C? Or should I just call it a C++
# api?

# TODO document, including vignettes

lua("a")
lua("a = 2")

L2 = lua_open()
lua("a = 4", L = L2)

lua("print(a)", L = NULL)
lua("print(a)", L = L2)
rm(L2)

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
"function(steps)
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
    print(x[0]+x[1]+x[2]+x[3]+x[4]+x[5]+x[6]+x[7]+
        x[8]+x[9]+x[10]+x[11]+x[12]+x[13]+x[14]+x[15])
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
    print(x[0]+x[1]+x[2]+x[3]+x[4]+x[5]+x[6]+x[7]+
        x[8]+x[9]+x[10]+x[11]+x[12]+x[13]+x[14]+x[15])
end")

cpptest = Rcpp::cppFunction(
"void cpptest(unsigned int steps) {
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

    Rcpp::Rcout << x[0]+x[1]+x[2]+x[3]+x[4]+x[5]+x[6]+x[7]+
        x[8]+x[9]+x[10]+x[11]+x[12]+x[13]+x[14]+x[15] << '\\n';

    delete[] x;
}")

rtest1 = function(steps)
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

    print(sum(x))
}

rtest2 = function(steps)
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

    print(sum(x))
}


system.time(luatest(5000))  # .3s
system.time(luatest_unroll(5000))  # .07s
system.time(cpptest(5000))  # .04s
system.time(rtest1(5000))   # 40s
system.time(rtest2(5000))   # 3s

