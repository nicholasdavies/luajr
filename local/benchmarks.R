bench::mark(
    luajr:::luajr_run_code("return nil", NULL),
    .Call(luajr:::`_luajr_run_code`, "return nil", NULL),
    min_time = 5
)

func = lua_func("function() return nil end")
bench::mark(
    func(),
    min_time = 5
)

# luajr_run, before removing Rcpp:
# A tibble: 1 × 13
# expression                                        min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory             time                gc
# <bch:expr>                                   <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list> <list>             <list>              <list>
# "luajr:::luajr_run(\"return nil\", 0, NULL)"   3.21µs   3.59µs   241271.    2.49KB     24.1  9999     1     41.4ms <NULL> <Rprofmem [1 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>

# after removing Rcpp:
# A tibble: 1 × 13
# expression                                          min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory             time                gc
# <bch:expr>                                     <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list> <list>             <list>              <list>
# "luajr:::luajr_run_code(\"return nil\", NULL)"   1.73µs   1.96µs   439693.        0B        0 10000     0     22.7ms <NULL> <Rprofmem [0 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>


# func, before removing Rcpp:
# A tibble: 1 × 13
# expression      min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory             time                gc
# <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list> <list>             <list>              <list>
# func()        3.1µs   3.68µs   224184.    2.49KB     22.4  9999     1     44.6ms <NULL> <Rprofmem [1 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>

# after removing Rcpp:
# A tibble: 1 × 13
# expression      min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory             time                gc
# <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list> <list>             <list>              <list>
# func()       2.31µs    2.6µs   318702.        0B        0 10000     0     31.4ms <NULL> <Rprofmem [0 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>


set.seed(12345)

v1 = rnorm(1e1)
v4 = rnorm(1e4)
v7 = rnorm(1e7)

lua("sum2 = function(x) local s = 0; for i=1,#x do s = s + x[i]*x[i] end; return s end")
sum2 = function(x) sum(x*x)
sum2_r = lua_func("sum2", "r")
sum2_v = lua_func("sum2", "v")
sum2_s = lua_func("sum2", "s")

# Comparing the results of each function:
sum2(v1)    # Pure R version
sum2_r(v1)  # luajr pass-by-reference
sum2_v(v1)  # luajr pass-by-value
sum2_s(v1)  # luajr pass-by-simplify

bench::mark(
    sum2(v1),
    sum2_r(v1),
    sum2_v(v1),
    sum2_s(v1),
    min_time = 5)

# A tibble: 4 × 13
# expression      min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result    memory              time                gc
# <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list>    <list>              <list>              <list>
# sum2(v1)     1.12µs   1.26µs   753549.    7.81KB      0   10000     0     13.3ms <dbl [1]> <Rprofmem [20 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_r(v1)   4.69µs   6.68µs   125157.    2.49KB     12.5  9999     1     79.9ms <dbl [1]> <Rprofmem [1 × 3]>  <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_v(v1)   6.32µs   7.19µs   109803.    2.49KB      0   10000     0     91.1ms <dbl [1]> <Rprofmem [1 × 3]>  <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_s(v1)   4.38µs   4.75µs   185003.    2.49KB     18.5  9999     1       54ms <dbl [1]> <Rprofmem [1 × 3]>  <bench_tm [10,000]> <tibble [10,000 × 3]>

# After remove Rcpp
# A tibble: 4 × 13
# expression      min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result    memory              time                gc
# <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list>    <list>              <list>              <list>
# sum2(v1)      994ns    1.2µs   687239.    7.81KB      0   10000     0     14.6ms <dbl [1]> <Rprofmem [20 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_r(v1)   3.33µs   3.58µs   178751.        0B      0   10000     0     55.9ms <dbl [1]> <Rprofmem [0 × 3]>  <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_v(v1)   4.58µs   5.06µs   163282.        0B     16.3  9999     1     61.2ms <dbl [1]> <Rprofmem [0 × 3]>  <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_s(v1)   2.91µs   3.15µs   302209.        0B      0   10000     0     33.1ms <dbl [1]> <Rprofmem [0 × 3]>  <bench_tm [10,000]> <tibble [10,000 × 3]>

bench::mark(
    sum2  (v4),
    sum2_r(v4),
    sum2_v(v4),
    sum2_s(v4),
    min_time = 5)

# A tibble: 4 × 13
# expression      min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result    memory             time                gc
# <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list>    <list>             <list>              <list>
# sum2(v4)     29.6µs   61.8µs    15770.   78.17KB    37.9   9976    24      633ms <dbl [1]> <Rprofmem [1 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_r(v4)   33.8µs   36.4µs    25742.    2.49KB     0    10000     0      388ms <dbl [1]> <Rprofmem [1 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_v(v4)   64.8µs   99.1µs    10101.    2.49KB     1.01  9999     1      990ms <dbl [1]> <Rprofmem [1 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_s(v4)   85.5µs   88.9µs    10918.    2.49KB     1.09  9999     1      916ms <dbl [1]> <Rprofmem [1 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>

# After remove Rcpp
# A tibble: 4 × 13
# expression      min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result    memory             time                gc
# <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list>    <list>             <list>              <list>
# sum2(v4)     30.4µs   60.8µs    15855.    78.2KB    23.8   9985    15      630ms <dbl [1]> <Rprofmem [1 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_r(v4)     34µs   34.5µs    26971.        0B     0    10000     0      371ms <dbl [1]> <Rprofmem [0 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_v(v4)   63.9µs   97.3µs    10426.        0B     0    10000     0      959ms <dbl [1]> <Rprofmem [0 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>
# sum2_s(v4)   80.2µs   85.2µs    11460.        0B     1.15  9999     1      872ms <dbl [1]> <Rprofmem [0 × 3]> <bench_tm [10,000]> <tibble [10,000 × 3]>

bench::mark(
    sum2  (v7),
    sum2_r(v7),
    sum2_v(v7),
    sum2_s(v7),
    min_time = 5)

# A tibble: 4 × 13
# expression      min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result    memory             time             gc
# <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list>    <list>             <list>           <list>
# sum2(v7)     37.1ms   38.2ms     25.7    76.29MB     69.0    29    78      1.13s <dbl [1]> <Rprofmem [1 × 3]> <bench_tm [107]> <tibble [107 × 3]>
# sum2_r(v7)   30.1ms     31ms     32.1     2.49KB      0     161     0      5.02s <dbl [1]> <Rprofmem [1 × 3]> <bench_tm [161]> <tibble [161 × 3]>
# sum2_v(v7)   71.8ms  106.8ms      7.57    2.49KB      0      38     0      5.02s <dbl [1]> <Rprofmem [1 × 3]> <bench_tm [38]>  <tibble [38 × 3]>
# sum2_s(v7)  116.2ms    158ms      5.73    2.49KB      0      29     0      5.06s <dbl [1]> <Rprofmem [1 × 3]> <bench_tm [29]>  <tibble [29 × 3]>

# After remove Rcpp
# A tibble: 4 × 13
# expression      min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result    memory             time             gc
# <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list>    <list>             <list>           <list>
# sum2(v7)     37.8ms   39.1ms     25.2     76.3MB     25.2    55    55      2.18s <dbl [1]> <Rprofmem [1 × 3]> <bench_tm [110]> <tibble [110 × 3]>
# sum2_r(v7)   30.4ms   31.3ms     31.8         0B      0     159     0         5s <dbl [1]> <Rprofmem [0 × 3]> <bench_tm [159]> <tibble [159 × 3]>
# sum2_v(v7)   70.4ms   97.5ms      7.29        0B      0      39     0      5.35s <dbl [1]> <Rprofmem [0 × 3]> <bench_tm [39]>  <tibble [39 × 3]>
# sum2_s(v7)  120.6ms  136.5ms      6.76        0B      0      34     0      5.03s <dbl [1]> <Rprofmem [0 × 3]> <bench_tm [34]>  <tibble [34 × 3]>

logistic_map_R = function(x0, burn, iter, A)
{
    result_x = numeric(length(A) * iter)

    j = 1
    for (a in A) {
        x = x0
        for (i in 1:burn) {
            x = a * x * (1 - x)
        }
        for (i in 1:iter) {
            result_x[j] = x
            x = a * x * (1 - x)
            j = j + 1
        }
    }

    return (list2DF(list(a = rep(A, each = iter), x = result_x)))
}

logistic_map_L = lua_func(
    "function(x0, burn, iter, A)
    local dflen = #A * iter
    local result = luajr.dataframe()
    result.a = luajr.numeric_r(dflen, 0)
    result.x = luajr.numeric_r(dflen, 0)

    local j = 1
    for k,a in pairs(A) do
        local x = x0
        for i = 1, burn do
            x = a * x * (1 - x)
        end
        for i = 1, iter do
            result.a[j] = a
            result.x[j] = x
            x = a * x * (1 - x)
            j = j + 1
        end
    end

    return result
end", "sssr")


microbenchmark::microbenchmark(
    logistic_map_R(0.5, 50, 100, 200:385/100),
    logistic_map_L(0.5, 50, 100, 200:385/100)
)
