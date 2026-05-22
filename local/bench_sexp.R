# Benchmark for to_sexp / from_sexp paths in luajr.
# Run before and after the refactor to compare.
#
# The most representative hot path is read_loop (VECSXP element read via
# from_sexp). Write loop and environment loop are also exercised. The
# constructor loop tests the table-input path that the refactor improves.

library(luajr)

# ---- Setup ----

# 10k-element list, mixed types
xs = as.list(c(rnorm(5000), as.list(sample(letters, 5000, replace = TRUE))))

# Pre-allocated empty list for writes
ys = vector("list", 10000)

# Environment with 100 named bindings
e = new.env()
for (i in 1:100) assign(paste0("v", i), i, envir = e)


# ---- Lua functions ----

# Read each list element (calls op_readv -> from_sexp 10k times per call)
# Note: each read allocates a wrapper cdata + PreserveObject, so this case
# is ~hundreds of times more expensive per inner iter than write_loop.
read_loop = lua_func("function(x)
    local s = 0
    for i = 1, #x do
        local v = x[i]
    end
    return s
end", "V")

# Write a number to each list element (10x inner loop). Hits to_sexp(number).
write_loop = lua_func("function(x)
    for k = 1, 10 do
        for i = 1, #x do x[i] = i * 2 end
    end
end", "&V")

# Write a string to each list element. Hits to_sexp(string).
write_string_loop = lua_func("function(x)
    for k = 1, 10 do
        for i = 1, #x do x[i] = 'hello' end
    end
end", "&V")

# Write a boolean to each list element. Hits to_sexp(boolean).
write_bool_loop = lua_func("function(x)
    for k = 1, 10 do
        for i = 1, #x do x[i] = (i % 2 == 0) end
    end
end", "&V")

# Write a reused cdata vector to each list element. Hits to_sexp(cdata),
# which falls through to the C path in the hybrid wrapper.
write_cdata_loop = lua_func("function(x)
    local v = luajr.numeric({1, 2, 3})
    for k = 1, 10 do
        for i = 1, #x do x[i] = v end
    end
end", "&V")

# Get from environment 100 times (from_sexp via R.get_var)
env_loop = lua_func("function(e)
    local s = 0
    for k = 1, 100 do
        for i = 1, 100 do
            local v = e:get('v' .. i)
        end
    end
end", "E")

# Set into environment 100 times (to_sexp via R.defineVar). Hits scalar
# to_sexp fast path through the hybrid wrapper.
env_set_loop = lua_func("function(e)
    for k = 1, 100 do
        for i = 1, 100 do e:set('v' .. i, i) end
    end
end", "E")

# Construct a small luajr.list from a Lua table 10000 times
# (exercises to_sexp's table path)
ctor_loop = lua_func("function()
    for i = 1, 10000 do
        local x = luajr.list({1, 2, 3, 4, 5, 6, 7, 8, 9, 10})
    end
end")

# Construct a small luajr.list from a Lua table with named keys 10000 times
# (currently broken without the fix, but should run after the refactor)
ctor_named_loop = lua_func("function()
    for i = 1, 10000 do
        local x = luajr.list({a=1, b=2, c=3, d=4, e=5})
    end
end")


# ---- Run benchmark ----

results = bench::mark(
    read_loop        = read_loop(xs),
    write_loop       = write_loop(ys),
    write_string_loop = write_string_loop(ys),
    write_bool_loop  = write_bool_loop(ys),
    write_cdata_loop = write_cdata_loop(ys),
    env_loop         = env_loop(e),
    env_set_loop     = env_set_loop(new.env()),
    ctor_loop        = ctor_loop(),
    ctor_named_loop  = ctor_named_loop(),
    iterations = 500,
    check = FALSE
)

print(results)

# Save with label so you can compare runs
# saveRDS(results, "local/bench_sexp_BEFORE.rds")
# saveRDS(results, "local/bench_sexp_AFTER.rds")
#
# Then to compare:
before = readRDS("local/bench_sexp_BEFORE.rds")
after  = readRDS("local/bench_sexp_AFTER.rds")
cbind(
    expression = before$expression,
    before_median = as.numeric(before$median),
    after_median  = as.numeric(after$median),
    ratio = as.numeric(after$median) / as.numeric(before$median)
)
