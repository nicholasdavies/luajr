# Lorenz attractor
library(luajr)
library(ggplot2)

step1 = function(x, rho, sigma, beta, dt)
{
    dx = sigma * (x[2] - x[1])
    dy = x[1] * (rho - x[3]) - x[2]
    dz = x[1] * x[2] - beta * x[3]
    x[1] = x[1] + dx * dt
    x[2] = x[2] + dy * dt
    x[3] = x[3] + dz * dt
    return (x)
}

lorenz1 = function(n, init, rho, sigma, beta)
{
    x = init
    result = matrix(0, nrow = n, ncol = 3)
    for (i in 1:n) {
        result[i, ] = x
        x = step1(x, rho, sigma, beta, 0.01)
    }
    return (result)
}

result = lorenz1(5000, c(1,1,1), 28, 10, 8/3)
plot(result[,1], result[,2], type = "l")


step2 = lua_func("
function(x, rho, sigma, beta, dt)
    local dx = sigma * (x[2] - x[1])
    local dy = x[1] * (rho - x[3]) - x[2]
    local dz = x[1] * x[2] - beta * x[3]
    x[1] = x[1] + dx * dt
    x[2] = x[2] + dy * dt
    x[3] = x[3] + dz * dt
    return x
end", "auto, native")

lorenz2 = function(n, init, rho, sigma, beta)
{
    x = init
    result = matrix(0, nrow = n, ncol = 3)
    for (i in 1:n) {
        result[i, ] = x
        x = step2(x, rho, sigma, beta, 0.01)
    }
    return (result)
}

result = lorenz2(5000, c(1,1,1), 28, 10, 8/3)
plot(result[,1], result[,2], type = "l")

lorenz3 = lua_func("
function(n, init, rho, sigma, beta)
    local step3 = function(x, rho, sigma, beta, dt)
        local dx = sigma * (x[2] - x[1])
        local dy = x[1] * (rho - x[3]) - x[2]
        local dz = x[1] * x[2] - beta * x[3]
        x[1] = x[1] + dx * dt
        x[2] = x[2] + dy * dt
        x[3] = x[3] + dz * dt
        return x
    end

    local x = init
    local result = luajr.matrix(n, 3)

    for i = 1,n do
        result[i] = x[1]
        result[i + n] = x[2]
        result[i + 2*n] = x[3]
        x = step3(x, rho, sigma, beta, 0.01)
    end

    return result
end", "$..$.$.$.")

bench::mark(
    lorenz1(5000, c(1, 1, 1), 28, 10, 8/3),
    lorenz2(5000, c(1, 1, 1), 28, 10, 8/3),
    lorenz3(5000, c(1, 1, 1), 28, 10, 8/3)
)
