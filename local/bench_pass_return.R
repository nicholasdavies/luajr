# Benchmark: old (r/v) vs new (R/V) arg codes for pass-in and return
library(luajr)

lua_reset()

lua("
local luajr = require('luajr')

-- Numeric: pass in, read all, return
function bench_numeric_old_r(x)
    local sum = 0
    for i = 1, #x do sum = sum + x[i] end
    return x
end

function bench_numeric_new_R(x)
    local sum = 0
    for i = 1, #x do sum = sum + x[i] end
    return x
end

function bench_numeric_old_v(x)
    local sum = 0
    for i = 1, #x do sum = sum + x[i] end
    return x
end

function bench_numeric_new_V(x)
    local sum = 0
    for i = 1, #x do sum = sum + x[i] end
    return x
end

-- Character: pass in, read all, return
function bench_char_old_r(x)
    local last
    for i = 1, #x do last = x[i] end
    return x
end

function bench_char_new_R(x)
    local last
    for i = 1, #x do last = x[i] end
    return x
end

function bench_char_old_v(x)
    local last
    for i = 1, #x do last = x[i] end
    return x
end

function bench_char_new_V(x)
    local last
    for i = 1, #x do last = x[i] end
    return x
end

-- Numeric: pass in, modify a few, return
function bench_numeric_modify_old_r(x)
    x[1] = 999
    x[#x] = 999
    return x
end

function bench_numeric_modify_new_R(x)
    x[1] = 999
    x[#x] = 999
    return x
end

function bench_numeric_modify_old_v(x)
    x[1] = 999
    x[#x] = 999
    return x
end

function bench_numeric_modify_new_V(x)
    x[1] = 999
    x[#x] = 999
    return x
end

-- Character: pass in, modify a few, return
function bench_char_modify_old_r(x)
    x[1] = 'z'
    x[#x] = 'z'
    return x
end

function bench_char_modify_new_R(x)
    x[1] = 'z'
    x[#x] = 'z'
    return x
end

function bench_char_modify_old_v(x)
    x[1] = 'z'
    x[#x] = 'z'
    return x
end

function bench_char_modify_new_V(x)
    x[1] = 'z'
    x[#x] = 'z'
    return x
end

-- Numeric: pass in, modify all, return
function bench_numeric_modall_old_r(x)
    for i = 1, #x do x[i] = x[i] + 1 end
    return x
end

function bench_numeric_modall_new_R(x)
    for i = 1, #x do x[i] = x[i] + 1 end
    return x
end

function bench_numeric_modall_old_v(x)
    for i = 1, #x do x[i] = x[i] + 1 end
    return x
end

function bench_numeric_modall_new_V(x)
    for i = 1, #x do x[i] = x[i] + 1 end
    return x
end

-- Character: pass in, modify all, return
function bench_char_modall_old_r(x)
    for i = 1, #x do x[i] = 'z' end
    return x
end

function bench_char_modall_new_R(x)
    for i = 1, #x do x[i] = 'z' end
    return x
end

function bench_char_modall_old_v(x)
    for i = 1, #x do x[i] = 'z' end
    return x
end

function bench_char_modall_new_V(x)
    for i = 1, #x do x[i] = 'z' end
    return x
end

-- Realistic: sort a numeric vector (quicksort)
local function qsort(x, lo, hi)
    if lo >= hi then return end
    local pivot = x.p[hi]
    local i = lo
    for j = lo, hi - 1 do
        if x.p[j] <= pivot then
            x.p[i], x.p[j] = x.p[j], x.p[i]
            i = i + 1
        end
    end
    x.p[i], x.p[hi] = x.p[hi], x.p[i]
    qsort(x, lo, i - 1)
    qsort(x, i + 1, hi)
end

function bench_sort_old_v(x)
    qsort(x, 1, #x)
    return x
end

function bench_sort_new_V(x)
    x:detach()
    qsort(x, 1, #x)
    return x
end

-- Realistic: Levenshtein distance between corresponding elements of two char vectors
-- Returns a numeric vector of distances
local function levenshtein(s, t)
    local slen, tlen = #s, #t
    if slen == 0 then return tlen end
    if tlen == 0 then return slen end
    local prev = {}
    local curr = {}
    for j = 0, tlen do prev[j] = j end
    for i = 1, slen do
        curr[0] = i
        for j = 1, tlen do
            local cost = (s:byte(i) == t:byte(j)) and 0 or 1
            curr[j] = math.min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
        end
        prev, curr = curr, prev
    end
    return prev[tlen]
end

-- All-in-Lua quicksort: generate random data, sort, return, repeated nreps times
-- This avoids the R->Lua->R transition on every rep
function bench_sort_allinlua_old(template, nreps)
    local N = #template
    local results = {}
    for rep = 1, nreps do
        local x = luajr.numeric(template)
        qsort(x, 1, N)
        results[rep] = x[1]  -- consume the result
    end
    return results[nreps]
end

function bench_sort_allinlua_new(template, nreps)
    local N = #template
    local results = {}
    for rep = 1, nreps do
        local x = luajr.numeric4(template)
        qsort(x, 1, N)
        results[rep] = x[1]  -- consume the result
    end
    return results[nreps]
end

function bench_levdist_old_r(a, b)
    local luajr = require('luajr')
    local out = luajr.numeric(#a, 0)
    for i = 1, #a do
        out[i] = levenshtein(a[i], b[i])
    end
    return out
end

function bench_levdist_new_R(a, b)
    local luajr = require('luajr')
    local out = luajr.numeric4(#a, 0)
    for i = 1, #a do
        out[i] = levenshtein(a[i], b[i])
    end
    return out
end
")

run_bench = function(label, data, ...) {
    names = list(...)
    codes = sub(".*_([rvRV])$", "\\1", names)
    funcs = mapply(function(n, c) lua_func(n, c), names, codes, SIMPLIFY = FALSE)
    cat(sprintf("\n=== %s ===\n", label))
    exprs = lapply(seq_along(funcs), function(i) bquote(.(funcs[[i]])(data)))
    names(exprs) = names
    print(do.call(bench::mark, c(exprs, list(min_iterations = 5, check = FALSE, filter_gc = FALSE))))
}

N = 10000L
num_data = as.numeric(1:N)
char_data = paste0("item", 1:N)

run_bench("Numeric read-all + return", num_data,
    "bench_numeric_old_r", "bench_numeric_new_R",
    "bench_numeric_old_v", "bench_numeric_new_V")

run_bench("Numeric modify-few + return", num_data,
    "bench_numeric_modify_old_r", "bench_numeric_modify_new_R",
    "bench_numeric_modify_old_v", "bench_numeric_modify_new_V")

run_bench("Char read-all + return", char_data,
    "bench_char_old_r", "bench_char_new_R",
    "bench_char_old_v", "bench_char_new_V")

run_bench("Char modify-few + return", char_data,
    "bench_char_modify_old_r", "bench_char_modify_new_R",
    "bench_char_modify_old_v", "bench_char_modify_new_V")

run_bench("Numeric modify-all + return", num_data,
    "bench_numeric_modall_old_r", "bench_numeric_modall_new_R",
    "bench_numeric_modall_old_v", "bench_numeric_modall_new_V")

run_bench("Char modify-all + return", char_data,
    "bench_char_modall_old_r", "bench_char_modall_new_R",
    "bench_char_modall_old_v", "bench_char_modall_new_V")

sort_data = runif(10000)
run_bench("Numeric quicksort (N=10000)", sort_data,
    "bench_sort_new_V", "bench_sort_old_v")

f_sort_lua_old = lua_func("bench_sort_allinlua_old", "vs")
f_sort_lua_new = lua_func("bench_sort_allinlua_new", "Vs")
cat("\n=== All-in-Lua quicksort (N=10000, 100 reps) ===\n")
print(bench::mark(
    new = f_sort_lua_new(sort_data, 100),
    old = f_sort_lua_old(sort_data, 100),
    min_iterations = 5,
    check = FALSE
))

words_a = sample(c("apple", "banana", "cherry", "date", "elderberry",
                    "fig", "grape", "honeydew", "kiwi", "lemon"), N, replace = TRUE)
words_b = sample(c("apricot", "blueberry", "cranberry", "dragonfruit", "elderflower",
                    "feijoa", "guava", "huckleberry", "jackfruit", "lime"), N, replace = TRUE)
f_lev_old = lua_func("bench_levdist_old_r", "rr")
f_lev_new = lua_func("bench_levdist_new_R", "RR")
cat("\n=== Levenshtein distance (N=10000) ===\n")
print(bench::mark(
    old_r = f_lev_old(words_a, words_b),
    new_R = f_lev_new(words_a, words_b),
    min_iterations = 5,
    check = FALSE
))
