library(luajr)
library(ggplot2)
library(data.table)
library(Rcpp)

lua(filename = "./local/odetest.lua")
runner = lua_func("run")

sol <- runner()

rm(sol)

bench::mark(
    sol <- runner()
)

ggplot(sol) +
    geom_line(aes(t, S)) +
    geom_line(aes(t, I)) +
    geom_line(aes(t, R))

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

yini = c(S = 0.999, I = 0.001, R = 0.000)
times = seq(1, 1000, by = 1)

bench::mark(
    out <- ode(yini, times, gradient, c(), method = "rk4")
)

out = as.data.table(out)

ggplot(out) +
    geom_line(aes(time, S)) +
    geom_line(aes(time, I)) +
    geom_line(aes(time, R))


# deSolve Rcpp version

cppFunction(
    'List gradient2(double t, Rcpp::NumericVector x, SEXP pars)
    {
        double dS = -0.05 * x[1] * x[0];
        double dI =  0.05 * x[1] * x[0] - 0.025 * x[1];
        double dR = 0.025 * x[1];
        return List::create(NumericVector::create(dS, dI, dR));
    }')

yini = c(S = 0.999, I = 0.001, R = 0.000)
times = seq(1, 1000, by = 1)

bench::mark(
    out <- ode(yini, times, gradient2, c(), method = "rk4")
)

out = as.data.table(out)

ggplot(out) +
    geom_line(aes(time, S)) +
    geom_line(aes(time, I)) +
    geom_line(aes(time, R))
