library(luajr)
library(ggplot2)
library(profvis)

# TO DO
# Tag luajr module with =
# Add "pv" function below to package?

lua(filename = "./local/profile3.lua")

lua_mode(profile = "f",
    lua("local f = function(x)
    x = math.sin(x)
    return math.exp(x)
end

local s = 0
for i = 1,10^7 do
    s = s + i
    s = f(s) + g(s)
end
return s"))


prof = lua_profile()
pv(prof)

# expects Rprof format
# To generate, see docs for ?Rprof
pv = function(prof)
{
    out = "line profiling: sample.interval=10000"
    src = factor(prof$source)
    nsrc = length(levels(src))

    files = character(nsrc)
    for (i in seq_len(nsrc)) {
        s = levels(src)[i]
        if (substr(s, 1, 1) == "@") {
            files[i] = substr(s, 2, nchar(s))
        } else if (substr(s, 1, 1) == "=") {
            files[i] = NA
        } else {
            files[i] = tempfile()
            writeLines(s, files[i])
        }
    }
    basefiles = basename(files)
    files = paste0("#File ", seq_along(files), ": ", files)

    out = c(out, files)

    r = 1
    while (r <= nrow(prof)) {
        sl = prof$slice[r]
        line = ""
        while (prof$slice[r] == sl && r <= nrow(prof)) {
            line = paste0(line, as.integer(src[r]), "#", prof$currentline[r], ' "',
                if (prof$what[r] == "main") paste0("<main:", basefiles[src[r]], ">") else prof$name[r], '" ')
            r = r + 1
        }
        out = c(out, line)
    }

    tc = textConnection(out)
    x = profvis::profvis(prof_input = tc)
    close(tc)

    x
}

pv(prof)


# Note: source: the source of the chunk that created the function. If source
# starts with a '@', it means that the function was defined in a file where the
# file name follows the '@'. If source starts with a '=', the remainder of its
# contents describe the source in a user-dependent manner. Otherwise, the
# function was defined in a string where source is that string.

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

lua("jit.on()")
lua_mode(profile = TRUE, logistic_map_L(0.5, 10000, 1000, 20000:38500/10000))
prof = lua_profile()
pv(prof)






# For fun - raytracing
lua_mode(profile = TRUE)
rt = lua(filename = "./local/raytrace.lua")
lua_mode(profile = FALSE)

prof = lua_profile()
pv(prof)

r = sapply(rt[[1]], `[[`, "r")
g = sapply(rt[[1]], `[[`, "g")
b = sapply(rt[[1]], `[[`, "b")

# Create RGB array (values 0-1)
width = 400
height = 300
img = array(0, dim = c(height, width, 3))
img[,,1] = matrix(r, ncol = 400, nrow = 300, byrow = TRUE) / 255
img[,,2] = matrix(g, ncol = 400, nrow = 300, byrow = TRUE) / 255
img[,,3] = matrix(b, ncol = 400, nrow = 300, byrow = TRUE) / 255

# Convert to raster
img_raster = as.raster(img)

# Display
plot(0:1, 0:1, type = "n", xlab = "", ylab = "", asp = 1)
rasterImage(img_raster, -0.166, 0, 1.166, 1)

