# luajr version?

library(luajr)
library(ggplot2)
library(data.table)

lua(paste0("luajr_dynlib_path = \"", getLoadedDLLs()[["luajr"]][["path"]], "\""))
lua(filename = "./local/odetest.lua")
runner = lua_func("run")

rm(sol)

bench::mark(
    sol <- runner()
)

ggplot(sol) +
    geom_line(aes(t, S)) +
    geom_line(aes(t, I)) +
    geom_line(aes(t, R))


library(deSolve)

beta = 0.5
gamma = 0.25

gradient = function(t, x, pars)
{
    dS = -beta * x[["I"]] * x[["S"]]
    dI =  beta * x[["I"]] * x[["S"]] - gamma * x[["I"]]
    dR = gamma * x[["I"]]
    return (list(c(dS, dI, dR)))
}

yini = c(S = 0.999, I = 0.001, R = 0.000)
times = seq(0, 1000, by = 1)

bench::mark(
    out <- ode(yini, times, gradient, c(), method = "rk4")
)

out = as.data.table(out)

ggplot(out) +
    geom_line(aes(time, S)) +
    geom_line(aes(time, I)) +
    geom_line(aes(time, R))
