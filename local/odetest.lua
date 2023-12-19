local ffi = require('ffi')
local luajr = require('luajr')

beta = 0.05
gamma = 0.025

function gradient(t, x, dxdt)
    dxdt.S = -beta * x.I * x.S
    dxdt.I =  beta * x.I * x.S - gamma * x.I
    dxdt.R = gamma * x.I
end

function rk4_step(t, h, x, k1, k2, k3, k4, q)
    -- Copy current state to q
    q.S = x.S
    q.I = x.I
    q.R = x.R

    -- Calculate Runge-Kutta 4 gradients
    -- k1
    gradient(t, x, k1)

    -- k2
    t = t + h/2
    x.S = q.S + h/2 * k1.S
    x.I = q.I + h/2 * k1.I
    x.R = q.R + h/2 * k1.R
    gradient(t, x, k2)

    -- k3
    x.S = q.S + h/2 * k2.S
    x.I = q.I + h/2 * k2.I
    x.R = q.R + h/2 * k2.R
    gradient(t, x, k3)

    -- k4
    t = t + h/2
    x.S = q.S + h * k3.S
    x.I = q.I + h * k3.I
    x.R = q.R + h * k3.R
    gradient(t, x, k4)

    -- update x
    x.S = q.S + h/6 * (k1.S + 2 * k2.S + 2 * k3.S + k4.S);
    x.I = q.I + h/6 * (k1.I + 2 * k2.I + 2 * k3.I + k4.I);
    x.R = q.R + h/6 * (k1.R + 2 * k2.R + 2 * k3.R + k4.R);
end

function run()
    -- Set up initial state
    x = { S = 0.999, I = 0.001, R = 0 }
    t = 0.0

    -- Set up temporary storage
    k1 = { S = 0, I = 0, R = 0 }
    k2 = { S = 0, I = 0, R = 0 }
    k3 = { S = 0, I = 0, R = 0 }
    k4 = { S = 0, I = 0, R = 0 }
    q = { S = 0, I = 0, R = 0 }

    -- Solution storage
    --df = luajr.Matrix(1000, 4, {"t", "S", "I", "R"})
    df = luajr.DataFrame(1000, 4, {"t", "S", "I", "R"})

    for t = 0,999 do
        df.t[t] = t
        df.S[t] = x.S
        df.I[t] = x.I
        df.R[t] = x.R

        rk4_step(t, 1.0, x, k1, k2, k3, k4, q)
    end

    return df
end
