# Benchmark individual components of the luajr call path.
# Measures costs of from_sexp, to_sexp, registry lookup, pcall, etc.
# by calling Lua functions that isolate each component.
library(luajr)

bench = function(..., n = 100000, env = parent.frame())
{
    bench::mark(..., min_iterations = n, max_iterations = n, filter_gc = FALSE, env = env)
}

lua("R = require('R')")
lua("local ffi = require('ffi')")

yini = c(S = 0.999, I = 0.001, R = 0.000)

# Pre-allocate reusable storage for gradient
lua("
save_d = luajr.numeric(3, 0)
save_l = R.allocVector(R.VECSXP, 1)
R.PreserveObject(save_l)
R.SET_VECTOR_ELT(save_l, 0, save_d.s)
")

# --- Lua-side component functions called 1000x in a loop ---
# These measure per-iteration cost of each component.

# A: Pure Lua arithmetic (the actual gradient computation, no R interaction)
lua("
function bench_A()
    local S, I, R = 0.999, 0.001, 0
    for i = 1, 1000 do
        local dS = -0.05 * I * S
        local dI =  0.05 * I * S - 0.025 * I
        local dR = 0.025 * I
    end
end
")

# B: Lua arithmetic + write results to luajr.numeric
lua("
function bench_B()
    local S, I, R = 0.999, 0.001, 0
    for i = 1, 1000 do
        save_d[1] = -0.05 * I * S
        save_d[2] =  0.05 * I * S - 0.025 * I
        save_d[3] = 0.025 * I
    end
end
")

# C: from_sexp for a scalar double (REALSXP length 1, 's' argcode)
lua("
function bench_C(s)
    local ffi = require('ffi')
    local x = ffi.cast(R.sexp, s)
    for i = 1, 1000 do
        local v = R.REAL(x)[0]
    end
end
")

# D: from_sexp for a numeric vector by reference ('r' argcode)
lua("
function bench_D(s)
    local ffi = require('ffi')
    local x = ffi.cast(R.sexp, s)
    for i = 1, 1000 do
        local v = luajr.numeric(x, -1)
    end
end
")

# E: to_sexp for a scalar double
lua("
function bench_E()
    for i = 1, 1000 do
        local r = R.ScalarReal(42.0)
    end
end
")

# F: to_sexp returning a pre-built SEXP (like gradient4 does)
lua("
function bench_F()
    for i = 1, 1000 do
        local r = save_l
    end
end
")

# G: TYPEOF check (used in from_sexp dispatch)
lua("
function bench_G(s)
    local ffi = require('ffi')
    local x = ffi.cast(R.sexp, s)
    for i = 1, 1000 do
        local t = R.TYPEOF(x)
    end
end
")

# H: R.length call
lua("
function bench_H(s)
    local ffi = require('ffi')
    local x = ffi.cast(R.sexp, s)
    for i = 1, 1000 do
        local n = R.length(x)
    end
end
")

# Wrap them
fA = lua_func("bench_A")
fB = lua_func("bench_B")
fC = lua_func("bench_C", "x")
fD = lua_func("bench_D", "x")
fE = lua_func("bench_E")
fF = lua_func("bench_F")
fG = lua_func("bench_G", "x")
fH = lua_func("bench_H", "x")

cat("=== Component costs (1000 iterations each, in Lua) ===\n")
print(bench(
    "A: pure arith"        = fA(),
    "B: arith + vec write" = fB(),
    "C: from_sexp scalar"  = fC(0.0),
    "D: from_sexp vec ref" = fD(yini),
    "E: to_sexp scalar"    = fE(),
    "F: to_sexp prebuilt"  = fF(),
    "G: TYPEOF"            = fG(yini),
    "H: R.length"          = fH(yini),
    n = 10000
))

# Full gradient call for comparison
gradient4 = lua_func("function(t, x, pars)
    save_d[1] = -0.05 * x[2] * x[1]
    save_d[2] =  0.05 * x[2] * x[1] - 0.025 * x[2]
    save_d[3] =                       0.025 * x[2]
    return save_l
end", "xrx")

cat("\n=== Full gradient call ===\n")
print(bench(
    "gradient4 single"     = gradient4(0, yini, c()),
    n = 100000
))

cat("\n=== Full gradient call 1000x ===\n")
print(bench(
    "gradient4 x1000"      = for (i in 1:1000) gradient4(0, yini, c()),
    n = 1000
))
