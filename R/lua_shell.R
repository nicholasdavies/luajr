#' Run an interactive Lua shell
#'
#' When in interactive mode, provides a basic read-eval-print loop with LuaJIT.
#'
#' As a convenience, lines starting with an equals sign have the `"="` replaced
#' with `"return "`, so that e.g. entering `=x` will show the value of `x` as
#' returned to R.
#'
#' @inheritParams lua
#'
#' @return Nothing.
#'
#' @export
lua_shell = function(L = NULL)
{
    # Short-circuit if not in interactive mode
    if (!interactive())
        return (invisible())

    # See if crayon package is available
    crayon_available = requireNamespace("crayon", quietly = TRUE);

    # Loop until blank line received
    line = "."
    prev_line = ""
    while (line != "")
    {
        # Read a line
        if (prev_line == "") {
            line = readline("lua > ")
        } else {
            # If we're building up multi-line input, show a special prompt
            line = readline(" +    ")
            if (line == "") {
                # Exit multi-line if nothing entered
                line = "."
                prev_line = ""
                next
            } else {
                # Otherwise build up input
                line = paste(prev_line, line)
            }
        }

        # If line starts with =, replace = with return
        if (substr(line, 1, 1) == "=") {
            xline = paste("return", substr(line, 2, nchar(line)))
        } else {
            xline = line
        }

        # Try to execute the line, capturing any error
        res = tryCatch(lua(xline, L = L), error = function(e) e)

        # If there is an error:
        if (is(res, "error")) {
            if (grepl("'<eof>'$", res$message)) {
                # Unexpected end of input: try to gather more input
                prev_line = line
                next
            } else if (crayon_available) {
                # Other error: show error message in red if possible
                cat(crayon::red(res$message), "\n")
            } else {
                # Or just in normal colour if not possible
                cat(res$message, "\n")
            }
        } else if (!is.null(res)) {
            # If line has returned a value, print it
            print(res)
        }

        prev_line = ""
    }
}
