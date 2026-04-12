library(luajr)
library(ggplot2)
library(data.table)
library(Rcpp)

# Independent Lua version
lua(filename = "./local/odetest.lua")
runner = lua_func("run")

sol <- runner()

rm(sol)

bench::mark(
    sol <- runner()
)

ggplot(sol) +
    geom_line(aes(time, S)) +
    geom_line(aes(time, I)) +
    geom_line(aes(time, R))

# deSolve R version
library(deSolve)

beta = 0.05
gamma = 0.025

gradient = function(t, x, pars)
{
    dS = -beta * x[["I"]] * x[["S"]]
    dI =  beta * x[["I"]] * x[["S"]] - gamma * x[["I"]]
    dR = gamma * x[["I"]]
    return (list(c(dS, dI, dR)))
}

# deSolve Rcpp version
cppFunction(
    'List gradient2(double t, Rcpp::NumericVector x, SEXP pars)
    {
        double dS = -0.05 * x[1] * x[0];
        double dI =  0.05 * x[1] * x[0] - 0.025 * x[1];
        double dR = 0.025 * x[1];
        return List::create(NumericVector::create(dS, dI, dR));
    }')

# deSolve Lua version
gradient3 = lua_func("function(t, x, pars)
    local d = luajr.numeric(3)
    d[1] = -0.05 * x[2] * x[1]
    d[2] =  0.05 * x[2] * x[1] - 0.025 * x[2]
    d[3] =                       0.025 * x[2]
    local l = luajr.list()
    l[1] = d
    return l
end", "xrx")

lua("R = require('R')")
lua("save_d = luajr.numeric(3, 0)")
lua("save_l = R.allocVector(R.VECSXP, 1)")
lua("R.PreserveObject(save_l)")
lua("R.SET_VECTOR_ELT(save_l, 0, save_d.s)")

gradient4 = lua_func("function(t, x, pars)
    save_d[1] = -0.05 * x[2] * x[1]
    save_d[2] =  0.05 * x[2] * x[1] - 0.025 * x[2]
    save_d[3] =                       0.025 * x[2]
    return save_l
end", "xrx")

yini = c(S = 0.999, I = 0.001, R = 0.000)
times = seq(1, 1000, by = 1)

gradient3(0, yini, c())

bench::mark(
    g <- gradient (0, yini, c()),
    g <- gradient2(0, yini, c()),
    g <- gradient3(0, yini, c()),
    g <- gradient4(0, yini, c())
)


bench::mark(
    out <- ode(yini, times, gradient, c(), method = "rk4"),
    out <- ode(yini, times, gradient2, c(), method = "rk4"),
    out <- ode(yini, times, gradient3, c(), method = "rk4"),
    out <- ode(yini, times, gradient4, c(), method = "rk4"),
    sol <- runner(),
    check = FALSE
)

out = as.data.table(out)

ggplot(out) +
    geom_line(aes(time, S)) +
    geom_line(aes(time, I)) +
    geom_line(aes(time, R))
