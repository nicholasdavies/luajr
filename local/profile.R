library(luajr)
library(data.table)
library(ggplot2)

plot_profile = function(p)
{
    pp = sort(unlist(p))
    dp = data.table(name = names(pp), time = unname(pp))
    dp = dp[order(time)]
    dp[, line := as.integer(stringr::str_extract(name, ":([0-9]+)\\|", group = 1))]
    dp[, func := stringr::str_extract(name, "\\|(.*)$", group = 1)]

    ggplot(dp[time > 2]) +
        geom_col(aes(y = time * 100 / sum(dp$time), x = func, fill = as.factor(line)), colour = "black") +
        geom_text(aes(y = time * 100 / sum(dp$time), x = func, label = line, group = line),
                  position = position_stack(vjust = .5)) +
        theme(legend.position = "none") +
        labs(x = "function", y = "Time (%)")
}


lua_mode(profile = TRUE,
    lua("local s = 0
        for i = 1,10^8 do
            s = s + i
            s = math.sin(s)
            s = math.exp(s)
        end
        return s"))

prof = lua_profile()
prof

plot_profile(prof)
